# 0009: APKG import feedback and metadata

## Decision

Expose coarse, truthful import phases and a structured result summary. Persist
only durable provenance on each imported deck—source filename and last successful
import date—while keeping per-operation counts as transient result values.
Keep the graph transaction off the main actor and extend rollback to media.
Define counts by Anki
identity and stage media with a rollback journal so a failed database save leaves
neither partial rows nor changed live media. The same final SwiftData save also
inserts a durable import commit marker keyed by the journal operation ID. Marker
presence after restart proves whether recovery must finalize or roll back media.
Attachment identity is note ID plus filename; new note-scoped paths replace the
current archive-number naming so unrelated imports cannot overwrite each other.
Shared App Group journals make pending recovery visible to the widget, while
the app repairs media in its existing private storage location.

## Why

An import can parse, decompress, copy media, upsert many records, repair a
schedule, and save. A single indefinite spinner gives no indication that work is
continuing, and re-import currently gives little explanation of what changed.
Durable provenance helps users recognize where a deck came from without turning
operational summaries into permanent model clutter.

## Alternatives considered

- Exact percentage progress — rejected because phases have package-dependent
  work and a fabricated percentage would be misleading.
- Save progress after every phase — rejected because it would break atomic
  rollback.
- Persist every historical import report — deferred; a latest-success marker and
  immediate result are sufficient for now.

## Consequences

Importer layers must report Sendable phase/result values without UI coupling.
Metadata changes only in the same successful final transaction. Re-import needs
well-defined added, updated, and deactivated counts. Every phase is emitted once,
including phases whose package-specific work count is zero.
Updated-card counts compare imported content and relationships rather than
timestamps, and remain disjoint from additions/deactivations. The summary
precedes mapping prompts; Config shows last-success provenance. Recovery gates
normal app use and new widget reads, preserves evidence when rollback itself
fails, and distinguishes storage errors from damaged input. The guarantee is
app-process termination recovery, not device power-loss or OS-crash durability.
There is one graph commit save; a separate marker-only cleanup save is allowed.
