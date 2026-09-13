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
      this slice; nothing in this app ever needs to actually erase a card
      row once created.
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
