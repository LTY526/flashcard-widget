# portable-library-backup-and-recovery

## Goal

Allow users to preserve and restore their complete app-owned flashcard library,
configuration, and progress without depending on SwiftData's private file
layout.

## Acceptance criteria

- [ ] Version 1 is a ZIP archive containing exactly `manifest.json`,
      `library.json`, and zero or more `media/<sha256-lowercase-hex>` files.
      `manifest.json` has required keys `formatIdentifier`, `version`,
      `createdAt`, `library`, and `mediaBlobs`. Their values are respectively
      `com.xyz7172.flashcard-widget.backup`, integer 1, an RFC 3339 UTC date, one
      object, and an array. `library` has `path` (`library.json`), `byteCount`, and
      `sha256`. Each unique mediaBlobs object has `path`, `byteCount`, and
      `sha256`, sorted by path; path must equal `media/<sha256>`. Unknown keys are
      ignored and every named key is required.
- [ ] The v1 envelope is non-ZIP64 ZIP32. It permits only stored (method 0) and
      deflate (method 8) regular-file entries, requires the UTF-8 filename flag,
      forbids encryption, multi-disk archives, symlinks, explicit directory
      entries, data descriptors (general-purpose bit 3), and duplicate names, and
      uses `/` paths normalized to Unicode NFC before validation. Each local and
      central header must exactly agree on raw/normalized filename, method, flags,
      CRC-32, compressed size, and uncompressed size before extraction. Writers
      emit manifest/library then media sorted by path; readers do not depend on
      entry order.
- [ ] ZIP flags must equal only UTF-8 bit 11; all other general-purpose bits are
      rejected. ZIP64, every local/central extra field, archive/entry comments,
      prepended data, and trailing data after the single EOCD are rejected. Every
      central entry maps to exactly one local header and every local header maps
      to exactly one central entry. Local-header offsets are unique; complete
      header/name/data ranges are contiguous from byte zero, non-overlapping,
      within bounds, and end exactly where the contiguous central directory
      begins; it ends exactly at the EOCD, which ends at file length. Extraction
      computes and matches CRC-32. A deflate decoder must consume exactly the
      declared compressed payload, reach end-of-stream with no trailing bytes,
      and produce exactly the declared uncompressed size. This applies to
      manifest.json as well as every other entry.
- [ ] `library.json` contains documented Codable records for every model and
      relationship, display mappings, deck configuration, current/watermark
      state, complete past/current/future entries, and import provenance. Stable
      identity uses imported Anki IDs where available; app-owned HistoryEntry is
      identified by `(deckAnkiID, sequence)` and DisplayConfig by deckAnkiID.
- [ ] Version 1 JSON is UTF-8 with required top-level arrays `decks`, `configs`,
      `noteTypes`, `fields`, `notes`, `cards`, `media`, and `history`. Dates are
      RFC 3339 UTC strings with fractional seconds; Int64 Anki IDs are decimal
      strings; other integers, booleans, and strings use native JSON types;
      optional values are present as null; media bytes exist only in media files.
- [ ] `fieldValues` is a JSON string array in the NoteType fields' ascending
      ordinal order. Every JSON integer fits signed 64-bit. Ordinals are
      `0...2147483647`; sequence/nextHistorySequence are
      `1...9223372036854775807`; sleep minutes are `0...1439`; byte counts are
      nonnegative and also obey the ZIP limits below.
- [ ] Version 1 record keys are exact. Deck: `ankiDeckID`, `name`, `createdAt`,
      `updatedAt`, `isPaused`, `nextHistorySequence`, `highestReachedSequence`,
      `activeSequence`, `sourceFilename`, `lastImportedAt`. Config:
      `deckAnkiID`, `orderRawValue`, `intervalMinutes`, `sleepEnabled`,
      `sleepStartMinute`, `sleepEndMinute`, `scheduleTimeZoneIdentifier`.
      NoteType: `ankiNoteTypeID`, `name`, `createdAt`. Field:
      `ankiNoteTypeID`, `ordinal`, `name`, `roleRawValue`. Note: `ankiNoteID`,
      `fieldValues`, `removedAt`, `createdAt`, `updatedAt`, `ankiNoteTypeID`.
      Card: `ankiCardID`, `ordinal`, `removedAt`, `createdAt`, `updatedAt`,
      `ankiNoteID`, `ankiDeckID`. Media: `ankiNoteID`, `ankiFilename`,
      `createdAt`, `sha256`; the hash links to one manifest media blob and
      multiple Media records may share that deduplicated blob. History:
      `ankiDeckID`, `sequence`, `projectedAt`, `ankiCardID`. Unknown keys are
      ignored; every listed key is required.
- [ ] Media references form a blob-level bijection: every distinct sha256 used by
      a library Media record has exactly one matching mediaBlobs object and ZIP
      entry; every mediaBlobs object has exactly one ZIP entry and at least one
      Media reference. Orphan, missing, duplicate, size-mismatched, or
      hash-mismatched blobs reject the archive.
- [ ] Enum domains are exact: Config.orderRawValue is `sequential` or `random`;
      Field.roleRawValue is null, `primary`, `secondary`, `tertiary`, or
      `quaternary`. Nullable keys are only Deck.highestReachedSequence,
      Deck.activeSequence, Deck.sourceFilename, Deck.lastImportedAt,
      Config.scheduleTimeZoneIdentifier, Field.roleRawValue, Note.removedAt,
      Card.removedAt, and History.ankiCardID. All other keys are non-null.
- [ ] Backup version 1 is implemented only after
      `tabbed-deck-detail-and-simplified-config` removes `newCardsADay` and
      `reviewPreviousDayCards`. They are intentionally absent because they never
      affected scheduling. An older store is migrated before export, and
      round-trip tests use the post-0007 schema.
- [ ] Stable keys are each nonzero Anki ID for its imported record type;
      `(ankiNoteTypeID, ordinal)` for Field; `(ankiNoteID, ankiFilename)` for
      Media; `(ankiDeckID, sequence)` for History; and `ankiDeckID` for Config.
      Export fails rather than inventing a fallback when an ID is zero/missing,
      a composite key duplicates, or a required relationship target is absent.
      Null is allowed only for date/config/pointer values that are optional in
      the model and for History.ankiCardID when its card was deleted.
- [ ] Relationship/cardinality validation is exact: each Deck has exactly one
      Config and each Config targets one Deck; each NoteType has Fields with
      unique contiguous ordinals `0..<fieldCount`; each Note.fieldValues count
      equals that fieldCount and its NoteType exists; each Card references one
      existing Deck and Note; each Media references one Note; each History
      references one Deck and, when ankiCardID is non-null, that Card exists and
      belongs to the same Deck. Every Field must target an existing NoteType.
      Deck and NoteType are graph roots; a Deck may have no cards, a NoteType may
      have no notes, and a soft-deleted Note may have no inbound Card, so those
      cases are valid rather than rejected as unreachable. No Config, Field,
      Card, Media, or History may lack its required owner/reference above.
- [ ] Card.ankiCardID is globally unique and `(ankiNoteID, ordinal)` is unique;
      duplicate card template ordinals for one Note reject the archive.
- [ ] The archive uses documented app-owned Codable representations rather than
      SwiftData table names, PersistentIdentifier values, or copied live
      Flashcards.store/WAL/SHM files.
- [ ] Export acquires shared ScheduleFileLock before resolving the active
      generation, opens one fresh ModelContainer/ModelContext, projects every
      model to immutable Codable values, reads/hashes media, and finishes the
      temporary archive while retaining that lock. Exclusive app mutations
      therefore cannot overlap the snapshot. It then releases the lock and uses
      the system file exporter without modifying the library.
- [ ] Before extraction, restore rejects an archive whose file length exceeds
      2,147,483,648 bytes or with
      more than 10,000 entries. During bounded streaming extraction it rejects
      an entry over 256 MiB uncompressed, total uncompressed bytes at or above
      4,294,967,295 bytes, a per-entry compression ratio over 200:1, duplicate
      normalized paths, symlinks, absolute
      paths, `..` traversal, backslash traversal, or any path outside the staging
      directory. Limits are checked before allocation where metadata permits.
      Ratio is `uncompressedSize / compressedSize`; zero/zero has ratio 1, while
      positive uncompressed size with zero compressed size is rejected.
- [ ] Restore validates the exact format identifier/version, required files,
      JSON schemas, unique stable identities, relationships, schedule invariants,
      declared sizes, and every SHA-256 in an operation-specific staging
      directory before changing active state. Version 1 is accepted; versions
      greater than 1 and malformed/zero versions are rejected. When version 2 is
      introduced, it must add a pure tested v1-to-v2 migration before v1 support
      may be removed.
- [ ] Schedule validation is exact per deck: sequences are unique positive
      integers; `nextHistorySequence` exceeds every stored sequence; every
      History deck/card reference resolves except a nullable deleted-card
      reference. Valid pointer states are: both pointer/watermark nil (no current,
      every entry upcoming); both non-nil with activeSequence equal to watermark
      and resolving to one renderable entry; or activeSequence nil with non-nil
      watermark whose same-sequence History row is non-renderable because its
      ankiCardID is null, its referenced Card.removedAt is non-null, or its
      referenced Note.removedAt is non-null—the supported pointer clear. Other
      pairs are invalid. With a
      watermark, sequences below/equal/above it are past/current-position/future;
      a renderable current is required only when activeSequence is non-nil.
      With nil watermark, every History entry is future for ordering/count/pause
      rules and there is no current. Renderable means its Card is non-null and
      active, its Note exists and is active, and Card.ankiDeckID equals
      History.ankiDeckID. When future rows are sorted by sequence ascending,
      both sequence and projectedAt are strictly increasing; at most 100 future
      entries exist, and every future entry is renderable by the definition
      above. A paused deck has
      no future entries. Config order is exactly `sequential` or `random`;
      intervalMinutes is `15...1440`; sleep endpoints are `0...1439` and differ
      when enabled; a non-null timezone resolves through `TimeZone(identifier:)`.
      These fixed v1 rules do not inherit future scheduler changes. Any violation
      rejects before active state changes.
- [ ] SharedModelContainer resolves an App Group `active-library.json` pointer
      only after acquiring ScheduleFileLock. The pointer names one UUID generation
      directory under `libraries/<uuid>/` containing `Flashcards.store` and
      `media/`.
- [ ] `active-library.json` is UTF-8 JSON with required keys `version` (integer
      1), `generationID` (canonical lowercase UUID), and `relativePath` (exactly
      `libraries/<generationID>`). Unknown keys are ignored. The standardized
      resolved path must remain below the App Group container and match the ID;
      symlinks are rejected.
- [ ] On cold launch with a legacy root store/media and no pointer, before any
      ModelContainer is created, adoption acquires the exclusive lock, copies the
      closed store plus WAL/SHM when present and media into a new UUID generation,
      reopens/verifies record counts and media hashes there, then atomically
      writes the pointer through the normal commit protocol. Failure leaves the
      legacy files authoritative. Legacy bytes are deleted only on a later launch
      after the selected generation opens successfully.
- [ ] Restore builds and opens a complete new generation from staged decoded
      values, saves it, closes it, reopens it read-only for invariant/count/hash
      verification, and does not modify the active generation. Before pointer
      commit it checkpoints/closes SwiftData, fsyncs store/retained sidecars,
      every media file, media/generation directories, and `libraries` directory.
- [ ] After explicit destructive confirmation, restore acquires the exclusive
      lock. Widget shared-lock acquisition waits/times out using existing rules,
      so no widget opens a generation during the switch. Restore writes a unique
      same-directory temporary pointer. It also writes pending content containing
      nullable oldGenerationID and non-null newGenerationID to a unique temporary
      marker, fsyncs it, atomically renames it to `pointer-commit.pending`, and
      fsyncs the directory. Only then does it fsync the temporary pointer,
      atomically rename that file over `active-library.json`, and fsync the pointer's parent
      directory before reporting success or releasing the lock. This pointer
      replacement is the sole commit point; before it all readers use the old
      generation, after it all newly opened contexts use the new generation.
- [ ] After pointer rename and parent fsync succeed, restore removes
      `pointer-commit.pending` and fsyncs its parent before reporting success. An
      unlink or final fsync failure is recovery-required (the new pointer remains
      active and no rollback occurs); launch recovery repeats pending cleanup
      idempotently.
- [ ] A termination during pending-marker temporary creation leaves no authoritative
      pending marker and the old pointer remains active; temporary markers are
      ignored and cleaned. A malformed authoritative pending marker is corruption,
      never guessed. Tests interrupt before/after marker fsync/rename/parent fsync.
- [ ] Every outcome after active-pointer rename—including pointer-parent fsync,
      pending unlink, or final parent-fsync failure—discards all old contexts and,
      before unlocking, opens exactly the generation named by the currently
      visible valid pointer. If visible pointer is new, it runs restore-completion
      reconciliation and requests one widget reload; if old, it does not reconcile
      restored data but still reloads the widget. The operation reports success
      only after all durability/cleanup steps; otherwise recovery-required. Tests
      inject pending unlink and final-fsync failures and assert context identity,
      reconciliation, reload count, lock release, and reported result.
- [ ] If rename succeeds but parent-directory fsync fails, restore discards old
      contexts, resolves/reopens whichever complete active pointer is visible,
      retains `pointer-commit.pending`, and reports recovery-required rather than
      ordinary failure/success. It never keeps contexts for a generation other
      than the visible pointer. On next launch under exclusive lock, a valid old
      or new pointer named by the pending record is accepted, its parent fsynced
      again, and the pending record removed and its parent fsynced; any other
      pointer is corruption. Tests inject rename failure and fsync failure both
      before and after rename.
- [ ] Legacy adoption uses the same pending schema with oldGenerationID null and
      the new UUID. Recovery accepts exactly either no active pointer (legacy
      remains authoritative) or the named new pointer; it fsyncs/cleans pending
      state using the same rules. Any other pointer is corruption. Normal restore
      requires non-null oldGenerationID matching the active pointer before commit.
- [ ] A failure or process termination before pointer replacement leaves the old
      generation active and the incomplete new directory removable on next
      launch. Termination after rename but before parent fsync may retain either
      the complete old or complete new pointer; both generations remain valid and
      launch selects whichever complete pointer survived. Temporary pointer files
      are never selected and are cleaned after the active pointer validates. A
      pending record triggers the recovery rule above. Only
      after parent fsync may restore report durable new selection. Old generations
      are removed only after a later launch confirms the active generation opens;
      cleanup failure does not roll back a committed restore.
- [ ] Successful restore discards every pre-switch ModelContainer/ModelContext,
      opens the selected generation, then reconciles it once at restore-completion
      `now` under the normal exclusive transaction and requests one debounced
      widget reload. Restore fidelity is asserted on the reopened generation
      before reconciliation; post-reconciliation differences are limited to the
      scheduler changes expected for elapsed time/timezone at that injected now.
      Existing widgets whose deck Anki ID exists resolve it; missing selections
      show Choose a deck.
- [ ] A separately confirmed Reset Library removes app-owned decks, models,
      schedules, and imported media by building a verified empty generation and
      switching the pointer through the identical exclusive-lock atomic commit
      protocol. The old generation remains until later cleanup. Reset then
      requests a widget reload and does not alter onboarding preferences.
- [ ] UI explains that uninstalling may remove App Group data and that APKG files
      do not contain app mappings/progress.
- [ ] App and widget tests prove neither caches a generation store URL/container
      across pointer switches and shared readers cannot overlap the exclusive
      commit point.
- [ ] Round-trip tests cover multiple decks, shared notes/media, all four roles,
      sleep/timezone config, current/future/past schedule state, and empty
      libraries. Failure tests prove atomicity for corrupt, unsupported, missing,
      duplicate, oversized, traversal, checksum, decompression-ratio, and
      interrupted archives; interruption tests execute immediately before and
      after the atomic pointer replacement.

## Scope-out

- Merge restore, selective-deck restore, iCloud sync, automatic backups,
  cross-device live synchronization, encryption/passwords, or APKG export.
- A production UI for raw SwiftData/SQLite inspection.
