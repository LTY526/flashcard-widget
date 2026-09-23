# 0011: Portable library backup and recovery

## Decision

Define a versioned, portable archive containing a manifest plus app-owned
library records and referenced media. Restore validates and stages the complete
archive before atomically switching the active library generation. The App Group
uses an atomically replaced pointer manifest to select a generation directory
containing its SwiftData store and media; the prior generation remains available
until the switch succeeds. Restore is a full-library replacement, not a merge,
and never exposes live SwiftData SQLite files as the user backup format.

## Why

App Group data may be removed with the app, and an original APKG does not contain
the user's mappings, schedule configuration, or progress. Copying SwiftData's
implementation-specific live SQLite files is unsafe and brittle across schema
versions. A documented application format permits validation and migration.

## Alternatives considered

- Export the SQLite store — rejected because table layout, WAL consistency, and
  model migration are implementation details.
- Merge a backup into the current library — deferred because identity conflicts
  and schedule reconciliation need a separate product decision.
- Cloud synchronization — out of scope; local Files export/import solves the
  immediate recovery need without accounts.

## Consequences

The archive format becomes a compatibility commitment and needs explicit schema
versions/migrations. Before opening a legacy store, existing installs are copied
and verified into their first UUID generation, then selected by the pointer;
legacy bytes remain until later successful cleanup. App and
widget must resolve the active generation after acquiring the shared schedule
lock rather than caching a store URL indefinitely. Restore requires temporary
space and an exclusive lock. Sensitive content remains unencrypted unless a
later decision adds encryption.

This decision depends on ADR 0007 removing `newCardsADay` and
`reviewPreviousDayCards` before backup version 1 ships. Those obsolete values
never affected scheduling and are intentionally excluded from the format.
