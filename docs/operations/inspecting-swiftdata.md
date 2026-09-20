# Inspecting the SwiftData store

[Documentation index](../README.md) | [Persistence and App Groups](../architecture/persistence-and-app-group.md)

SwiftData currently persists this project through SQLite, so its files can be
copied and inspected. Treat the generated schema as a debugging detail, not an
API, and never edit a live store behind SwiftData.

## Files to copy

The App Group container can contain:

~~~text
Flashcards.store
Flashcards.store-wal
Flashcards.store-shm
~~~

Copy all files with the app and widget stopped. Omitting a WAL file can make the
copy appear stale or inconsistent.

## Simulator

The safest way to locate the current path is to temporarily log the value
returned by FileManager.containerURL(forSecurityApplicationGroupIdentifier:)
in a debug build. Stop the app/widget, copy the three store files to a separate
folder, then open the copy read-only with a SQLite viewer or sqlite3.

Container UUID paths can change after reinstall, so do not document or code a
fixed path.

## Physical device

Xcode may allow downloading an app container, but App Group containers are not
always included or directly exposed like the main application sandbox. For
reliable diagnostics, add an explicit debug-only export that copies a closed,
consistent store snapshot into a shareable app location. Do not ship such an
export if card content is considered private.

## Reading the database

SwiftData table and column names are generated and may change with OS/toolchain
versions. Inspection is useful for confirming that rows exist, timestamps were
saved, or relationships look plausible. Business logic should be diagnosed
against the SwiftData models and DeckScheduler invariants, not by depending on
generated SQL names.

Never modify or replace the installed database while either process may be
running. That bypasses ModelContext tracking, the schedule lock, migration, and
WAL coordination and can corrupt the library.
