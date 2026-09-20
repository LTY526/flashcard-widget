# Data model

[Documentation index](../README.md)

The app uses SwiftData for its domain objects. SharedModelContainer lists the
complete schema; both targets must use that same schema when opening the store.

~~~text
NoteType 1 --- * NoteTypeField
    |
    *
   Note 1 --- * Card * --- 1 Deck 1 --- 1 DisplayConfig
    |             |              |
    *             +--------------* HistoryEntry
 MediaItem
~~~

| Model | Meaning |
|---|---|
| Deck | Imported deck and the root of schedule state |
| Card | Anki card identity; points to note and deck |
| Note | Raw Anki fields shared by one or more cards |
| NoteType | Anki model and its field definitions |
| NoteTypeField | Field ordinal/name and optional display role |
| DisplayConfig | Order, interval, sleep window, and scheduling timezone |
| HistoryEntry | One scheduled sequence position and projected display time |
| MediaItem | Imported media metadata belonging to a note |

## Display roles

Field mappings are stored on NoteTypeField, not copied into every card. Note
computes primary, secondary, tertiary, and quaternary content from its raw field
values. The widget displays the first three roles; expanded in-app content can
display all four without truncating the quaternary value.

## Schedule state

Deck stores the current schedule pointer/watermark and owns HistoryEntry rows.
An entry is interpreted as past, current, or future relative to that pointer;
these are not three separate databases. The scheduler maintains one current
entry and up to 100 future entries.

## Identity and deletion

Imported Anki identifiers are preserved so re-import can update existing rows.
Cards absent from a later import are soft-deleted where required, allowing
schedule repair without dangling relationships. Removing a whole deck uses
DeckRemover, which retains notes and media still referenced by another deck.

## Change checklist

When adding or changing a model:

1. Update SharedModelContainer for both executables.
2. Decide migration/default behavior for existing stores.
3. Check Codable/Sendable projection types used across isolation boundaries.
4. Add tests using the in-memory container in Fixtures.swift.
5. Verify app and widget can open the same installed store.
