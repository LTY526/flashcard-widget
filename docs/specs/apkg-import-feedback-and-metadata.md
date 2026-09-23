# apkg-import-feedback-and-metadata

## Goal

Make long and repeated APKG imports understandable, keep the UI responsive, and
make the database and media recover together after an interrupted import.

## Integration and recovery boundary

Build after `tabbed-deck-detail-and-simplified-config`. Import must flush pending
Next work through its root coordinator before beginning graph mutation.
`ApkgImporter` currently saves the graph once under `ScheduleFileLock`, but
`MediaImporter` writes directly to private Application Support, skips existing
attachments, and can alias unrelated media paths. This plan adds file recovery;
it does not assume current media writes already roll back with SwiftData.

The recovery guarantee covers thrown errors and abrupt app-process termination.
The write-order checks below are required, but do not promise survival of device
power loss, an OS crash, or physical storage corruption. Generation-based backup
and moving all media into the App Group are separate work, not prerequisites.

The app owns recovery because existing media lives in its private
`MediaImporter.storageDirectory()`. Authoritative journals live in the shared
App Group `import-journals/<operation-uuid>.json`; their presence is also the
widget-visible pending indicator. Backup/staging bytes live under an
operation-specific directory in the private media root. Journal paths are
relative to those fixed roots, validated to remain inside them, and never taken
as arbitrary absolute paths from an archive. Journal creation writes a unique
temporary file, fsyncs it, renames it to the authoritative name, then fsyncs its
parent before touching live media. Orphan preparation directories/temporary
journals have no authority and can be cleaned if no journal or marker names them.

App startup uses a recovery-only context under the exclusive schedule lock before
exposing normal ContentView/model contexts. The same gate applies to activation,
import/re-import, removal, Next, pause, config, and field-mapping entry points.
Before library reads, widget timelines and DeckEntity queries check shared
journals and ImportCommitMarkers under their shared lock. Pending evidence or
an unreadable recovery state yields the unavailable widget state / a query
error, never partial deck choices; the widget does not repair private media.
An already-issued immutable widget timeline may remain visible until WidgetKit
reloads it. The gate concerns new reads, not recalling existing timelines.

Use one fresh non-autosaving worker context, created after acquiring the exclusive
lock, for the graph transaction and marker. Parsing may happen beforehand. Retain
the lock through media installation, graph commit, and finalization/rollback.
Release it only after a clean outcome or after preserving recovery evidence and
closing the normal-library gate. Recovery success refreshes main-context data
and requests one widget reload before normal library use resumes.

## Acceptance criteria

- [ ] The importer reports these monotonic coarse phases through a Sendable,
      UI-independent progress API: Opening Package, Reading Collection, Importing
      Cards, Importing Media, Updating Schedule, and Saving.
- [ ] Each phase above is emitted exactly once in that order for a successful attempt;
      none is skipped or repeated when a phase has zero items. An error stops
      emission immediately, so phases after the failure are not emitted.
- [ ] The import UI displays the latest reported phase and prevents conflicting
      library mutations while work is active without blocking ordinary UI
      rendering on the main actor. Parsing, model work, file work, and recovery
      run away from the main actor; only Sendable phase/result values cross to UI.
- [ ] Success presents: unique decks affected, cards added, cards updated, cards
      deactivated, media imported, and note types still requiring mapping.
      `removed` is not a separate/combined label.
- [ ] Imported deck IDs are exactly the IDs referenced by imported cards,
      including Unknown Deck fallbacks when metadata is absent. Unreferenced
      parent/empty deck metadata does not create/update a deck, preserving current
      importer behavior. An attempt is an Update when any such ID existed before
      the transaction, otherwise a New Import. Identity is `ankiDeckID`,
      `ankiCardID`, `ankiNoteID`, or `ankiNoteTypeID` for each corresponding model;
      a media attachment is keyed by `(ankiNoteID, ankiFilename)`.
- [ ] Counting definitions are exact and count each stable identity at most once
      per operation: added card = no pre-transaction Card with that Anki ID;
      updated card = a present existing card whose ordinal, note/deck Anki ID,
      card/note active state, or imported note fieldValues/note-type Anki ID
      changes. Compare pre-transaction and proposed values, excluding timestamps,
      provenance, mappings, and schedule changes. Text-only changes count every
      present existing card referencing that changed note once; cards absent
      from the package do not join this updated set. Deactivated card =
      a previously active existing card in an affected deck absent from the new
      package and soft-deleted by this transaction. A reactivated card counts as
      updated, not added. The three card sets are disjoint. Decks affected is the
      number of unique imported deck
      IDs whose deck/card/note/config/provenance state changes.
- [ ] Media imported counts unique logical Anki filenames for which at least one
      imported attachment is new or its bytes differ from that attachment's
      pre-transaction bytes. Identical bytes count zero even when their physical
      path migrates; multiple changed references to one filename count once.
      Affected note types are the unique note-type IDs referenced by imported
      notes. The mapping count includes exactly those whose post-import primary
      mapping is incomplete, including previously imported note types.
- [ ] Imported attachments use collision-free note-scoped destinations:
      `Media/v2/<decimal-ankiNoteID>/<sha256-of-UTF8-ankiFilename>`. No path uses
      an archive entry number or a lossy sanitized filename. Existing attachments
      with the same note/filename update to the incoming bytes, while unrelated
      notes retain their bytes even when filenames or old paths coincide. Do
      not share new physical files across different notes. If distinct logical
      keys would resolve to one destination, reject before live-file mutation.
      Legacy paths remain valid for untouched attachments; remove an old path
      only when the post-import graph has no reference to it, with that deletion
      covered by the same journal. Deck removal respects remaining path
      references so shared legacy files are not deleted prematurely.
- [ ] Unreferenced package media is ignored. A referenced filename absent from
      the package media map leaves its existing attachment unchanged, or creates
      no attachment if none existed. A mapped referenced file that is missing or
      cannot be read rejects as damaged-package input. Duplicate logical media
      filenames with conflicting payloads reject before mutation. Re-import
      does not remove an attachment merely because its tag disappeared from
      note text; attachment pruning remains outside this change.
- [ ] Each successfully imported deck persists the user-visible source filename
      and last-successful-import Date. These values update only if the complete
      import transaction saves successfully. Config shows these read-only values
      with a locale-formatted date; pre-feature decks show no provenance until
      their next successful import. One successful-import timestamp is injected
      per operation. Add an on-disk old-schema migration test for the nullable
      metadata properties and ImportCommitMarker model.
- [ ] A dismissible success summary appears before the existing mapping-prompt
      sequence. Dismissing the summary continues mapping prompts under existing
      rules; the summary's incomplete-mapping count also tells users what can be
      reopened from Config. No success summary appears on failure or while
      recovery is required.
- [ ] Media writes first enter an operation-specific staging directory. Before
      changing live files, a rollback journal records every target as absent or
      records its original bytes/location and SHA-256. The journal and all
      backup/staged bytes are written and fsynced before the first live-file
      mutation. Fsync every changed staging/backup directory and its parent
      chain through the operation root before publishing the journal using the
      atomic creation protocol above. Journal records include installed hashes
      and enough original-file data to restore each target idempotently.
- [ ] After model mutation, staged media is installed. Every installed live file
      and every parent directory changed by create, replace, rename, or deletion
      is fsynced before the transaction's single ModelContext save atomically
      writes both imported model changes and an
      `ImportCommitMarker` containing the journal UUID. That save is the commit
      boundary. On ordinary install/save failure before commit, rollback restores
      replaced files, removes newly created live files/staging, rolls back and
      discards the context, fsyncs restored paths, then removes the journal.
- [ ] Pre-commit rollback fsyncs each restored file and every directory affected
      by restoration/deletion/rename and verifies the original target states
      before removing the journal, then fsyncs the journal parent. Keep original
      backup bytes until every target is restored and verified. If restore,
      delete, verification, or fsync fails, retain the journal and remaining
      backup/staged evidence, discard the model context, report recovery-required,
      and leave normal library use gated. Retry uses the same operation ID and
      idempotently resumes rollback; it does not begin a new import.
- [ ] After successful commit, finalization verifies installed hashes, removes
      backup/staging files, then removes and fsyncs the journal before deleting
      ImportCommitMarker in a cleanup save. The marker contains the operation
      UUID plus final target states (relative path with SHA-256, or expected
      absence for a journaled deletion), so it remains sufficient recovery
      evidence after journal removal. Every step is idempotent. Cleanup failure
      leaves whichever evidence remains and reports recovery-required rather
      than undoing committed database changes.
- [ ] Before later import or library use, launch recovery acquires the exclusive
      schedule lock and scans the union of journals and ImportCommitMarkers. A
      journal without a marker is uncommitted and is rolled back. A journal plus
      marker is committed and resumes finalization. A marker without a journal
      means media finalization completed; recovery verifies its final-state list
      and deletes only the marker. Termination immediately before commit rolls
      back; termination immediately after commit or between journal and marker
      deletion finalizes. Recovery fsyncs changes before deleting last evidence.
      A malformed authoritative journal, unknown target root, or unreadable
      marker is recovery-required corruption and keeps the gate closed; never
      guess which files to delete. This recovery runs before all app/widget
      admissions described above, with the app performing repair and widgets
      only checking whether admission is allowed.
- [ ] For a committed journal plus marker, durable staged bytes remain until all
      live target hashes verify. A missing, torn, or mismatched target is
      reinstalled from staging and its file/parent directories fsynced before
      finalization. A marker-only mismatch reports recovery-required corruption
      and retains the marker; it never rolls back the committed database.
- [ ] Parser failures retain the existing invalid-package, damaged-collection,
      and unsupported-schema errors. Local disk/permission/model-save failures
      have a distinct storage/import-failed outcome, not a damaged-APKG message.
      Before commit, a completed rollback gives no summary or changed provenance;
      fresh inspection observes exactly the pre-attempt graph/media. Incomplete
      rollback instead reports recovery-required and permits only recovery Retry
      while keeping normal library use gated. Finalization failure after commit is
      instead recovery-required: committed graph/provenance/media are retained,
      no rollback is attempted, and journal and/or marker remains for idempotent
      recovery rather than being reported as an ordinary failed import.
- [ ] Progress reporting never performs a SwiftData model access across the
      wrong actor/context. There is exactly one graph commit save containing
      all imported changes and the marker; marker-only cleanup may use a separate
      save. No progress callback saves partial imported data.
- [ ] Tests cover exact phase emission through failure at each phase; every count
      definition; new/update classification; metadata persistence; identical,
      new, replaced, and multiply referenced media; injected install/save/cleanup
      failures; termination immediately before/after commit; idempotent recovery
      with and without a marker; durable write ordering; and responsiveness.
- [ ] Additional regression cases cover text-only/shared-note updates, disjoint
      updated/deactivated counts, unchanged re-import, ignored empty parent-deck
      metadata, media replacement and archive-entry renumbering, filename and
      shared-legacy-path collisions, interruption/failure during rollback,
      malformed recovery evidence, widget-first access, and recovery failure.
      Prove all mutation entry points are gated while recovery is pending and
      widget/entity reads expose no library values until repair completes.

## Scope-out

- Exact percentage/time-remaining estimates, cancellation, import history, or
  background execution after the app is terminated.
- ZIP64 support or new Anki schema/compression compatibility.
- Editing the source APKG or exporting an APKG.
- Device power-loss/OS-crash durability, storage-corruption repair, attachment
  pruning, or generation-based library replacement.
