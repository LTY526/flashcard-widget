# apkg-import

## Goal

Let a user import an Anki `.apkg` deck file into the app and have its decks,
note types, notes, and cards land in SwiftData, with each note type's fields
mapped to display roles the app can later use — the foundation the
scheduling engine and Lock Screen widget (future phases, see
[0001](../decisions/0001-anki-lockscreen-widget-architecture.md)) are built
on.

## Acceptance criteria

- [ ] User can pick a `.apkg` file from the Files app (e.g. via
      `.fileImporter`/`UIDocumentPickerViewController`) and trigger an import.
- [ ] The app unzips the `.apkg` and reads the embedded SQLite collection
      using an in-repo, independently written parser — no vendored Anki
      source (per [0001](../decisions/0001-anki-lockscreen-widget-architecture.md)).
      In scope: both the legacy `collection.anki2` container (older schema,
      decks/note-types stored as JSON in a single `col` row) and the modern
      `collection.anki21b` container (zstd-compressed, newer relational
      schema with dedicated `notetypes`/`decks`/`fields` tables) — the latter
      is what most `.apkg` files exported by current Anki versions actually
      use, so it is not optional. zstd decompression requires a third-party
      dependency (Apple's `Compression` framework has no zstd algorithm).
      The uncompressed, non-`b`-suffixed `collection.anki21` container is
      out of scope unless a real sample file in that exact form is found —
      note whether it was encountered or not. Detection of which variant a
      given `.apkg` uses must not rely on filename presence alone: modern
      exports contain a dummy stub `collection.anki2` (a placeholder note
      for old Anki clients) alongside the real `collection.anki21b` —
      prefer reading the `meta` file or probing the actual file contents
      over assuming "has `collection.anki2`" means "legacy container."
- [ ] Import produces SwiftData records for: decks, note types (with each
      note type's field names and order), notes (field values per note),
      and cards (linking a note to a deck, preserving Anki's card ordinal).
- [ ] Importing a second, different `.apkg` adds its decks alongside any
      already-imported decks (multiple decks coexist).
- [ ] Re-importing a `.apkg` for a deck already in the app (same Anki deck
      ID) updates that deck's notes/cards in place rather than creating a
      duplicate deck: existing notes/cards present in the new file are
      updated, new ones are added, and notes/cards that existed before but
      are absent from the re-imported file are **soft-deleted** (flagged
      removed, e.g. a `removedAt` timestamp) rather than deleted outright —
      they stop appearing in decks/UI and are excluded from future
      scheduling, but the row and any history/state attached to it (future
      scheduling phases will attach review/progress history to a card) is
      preserved rather than destroyed. Hard-deleting is out of scope for
      *this reconciliation path* — automatic re-import never erases a note
      or card row. The one exception is explicit, user-initiated deck
      removal (see below), which does hard-delete; that's deliberate user
      intent, not a side effect of importing an updated file.
- [ ] After import, for each new note type encountered with 2 or more
      fields, the user is prompted to map its fields to at least two roles:
      `primary` and `secondary` (e.g. for a Japanese vocab note type:
      Expression → primary, Reading + Meaning → secondary). Fields left
      unmapped are still stored, just unused by v1 display logic. A note
      type with only a single field maps that field to `primary` and skips
      the `secondary` prompt (no undefined "not enough fields" state).
- [ ] If the user dismisses the field-mapping prompt without completing it,
      the deck's notes/cards are still imported and stored — the note type
      is just left unmapped (no role assignments), and the deck is flagged
      in the UI as "needs field mapping" until the user completes it. Import
      never blocks or rolls back on an incomplete mapping.
- [ ] Field-role mappings are remembered per note type, so importing another
      deck that reuses a previously-seen note type does not re-prompt.
- [ ] Media files (images/audio) referenced by imported notes are copied into
      app storage and associated with their note, but are not required to
      render anywhere in this slice.
- [ ] Importing an invalid file never crashes the app and never mutates
      previously-imported data, and the shown error is specific to which of
      these cases occurred (a single generic "couldn't import" message does
      not satisfy this criterion):
      - Not a zip file, or a zip missing the expected collection file →
        "this doesn't look like an Anki deck file."
      - Zip opens but the collection database is corrupt/unreadable →
        "this deck file is damaged."
      - Collection schema version is newer/older than the two variants this
        app supports (see above) → "this deck was made with a version of
        Anki this app doesn't support yet."
      (A password-protected-zip case is not included: Anki's own exporter
      does not produce password-protected `.apkg` files, so there is no
      real fixture to test this against — don't build handling for a case
      that can't be produced by the software we're importing from.)
- [ ] An automated test imports real sample `.apkg` fixtures (small
      Japanese-vocab test decks checked into the repo/test target) covering
      both the `.anki2` and `.anki21b` container variants, and asserts the
      expected decks/note types/notes/cards exist in SwiftData afterward
      for each.
- [ ] An automated test imports a fixture, then re-imports a modified copy
      of the same fixture with one note (and its card) removed, and
      asserts: both the removed note's row and the removed card's row
      still exist in SwiftData, both are flagged as removed, and both are
      excluded from queries for "active" notes/cards in that deck.
- [ ] The `.apkg` file type is declared in the app's Info.plist
      (`UTImportedTypeDeclarations`, conforming to `public.zip-archive`),
      not just constructed at runtime via
      `UTType(filenameExtension:conformingTo:)` — the system file picker
      needs the declared type to recognize and allow selecting `.apkg`
      files from Files/iCloud/other providers; without it, matching files
      appear greyed out and unselectable.
- [ ] Each deck in the deck list can be removed via a destructive swipe
      action, gated by a confirmation dialog stating the action is
      permanent (but the source `.apkg` can be re-imported later).
- [ ] Removing a deck hard-deletes that deck and its cards (per ADR 0001,
      decision 8 — an explicit exception to decision 6's soft-delete
      policy, since this is deliberate user intent, not automatic
      reconciliation). A note is hard-deleted (along with its
      cascade-deleted media rows and the actual media files on disk) if it
      has no *active* card left outside the deck being removed. A note
      that still has an active card in another deck is left untouched,
      including its media. A note whose only other card is itself
      soft-deleted (e.g. removed by an earlier re-import) does **not**
      count as "still in use elsewhere" and must still be hard-deleted —
      otherwise it (and its media) leaks permanently with no path to ever
      being cleaned up.
- [ ] An automated test covers `DeckRemover`: removing a deck deletes its
      cards; a note used only by that deck is hard-deleted along with its
      media file on disk; a note with an active card in another deck
      survives, untouched, with its media intact; a note whose only other
      card is soft-deleted is still hard-deleted (not treated as shared).
- [ ] Field-role mapping is not a one-time prompt: the user can reopen the
      mapping sheet for any deck at any time via a swipe action ("Edit
      Mapping"), regardless of whether that deck's note types are already
      fully mapped.
- [ ] Reopening the mapping sheet for an already-mapped note type preloads
      its currently-saved roles, not a fresh heuristic guess; the
      heuristic default is only used the first time a note type is ever
      mapped.
- [ ] The mapping sheet shows a live preview (primary/secondary text) built
      from a random sample note of that note type, driven by the
      in-progress (unsaved) picker selections so it updates as the user
      changes them. A "Try another card" control picks a different sample
      note; disabled when fewer than two notes exist for that note type.
- [ ] Import runs without blocking the main thread: the app shows a
      progress indicator (toolbar spinner plus a dimmed overlay) while an
      import is in flight, and remains responsive throughout.
- [ ] Deck removal shows the same kind of in-progress indicator as import
      while it runs.

## Scope-out

- Scheduling/display strategy config (`interval`, `order`, `newCardsADay`,
  `reviewPreviousDayCards`, etc.) — separate future spec.
- The WidgetKit Lock Screen extension and any on-widget rendering, including
  the interactive "flip card" App Intent — separate future spec.
- Any live sync with Anki (AnkiConnect or AnkiWeb) — excluded from v1
  entirely per [0001](../decisions/0001-anki-lockscreen-widget-architecture.md);
  AnkiWeb sync specifically is excluded outright, not just deferred.
- Rendering media (images/audio) anywhere in the UI — stored now, used later.
- Replicating Anki's own SM-2/FSRS spaced-repetition algorithm — this app's
  future scheduling strategies are its own simpler sequencing rules, not a
  clone of Anki's scheduler.
- Visual/UI design polish or mockups — no design direction exists yet; a
  functional import flow is enough for this slice.
- Per-deck field-mapping overrides — a note type's mapping is global, not
  per-deck (see ADR 0001, decision 9, which leaves this an open question
  for a future pass rather than resolving it here).
- Any confirmation/undo mechanism beyond the single confirmation dialog for
  deck removal (e.g. a "recently removed" recovery view) — removal is
  immediate and permanent once confirmed.
