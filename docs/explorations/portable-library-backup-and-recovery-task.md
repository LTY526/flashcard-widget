# Explore portable library backup and recovery

Status: prepared for an exploration; no prototype or user feedback is recorded yet.
Branch: `codex/explore-portable-backup-recovery`.
Base: `origin/main` at `faa7927` (the five reviewed plans).

## Goal and confirmed scope

Preserve and restore the app's decks, mappings, configuration, progress,
history, and imported media through a portable local file. Restore replaces the
whole library. Merge restore, cloud sync, and encryption are outside the current
request. The copied [ADR](../decisions/0011-portable-library-backup-and-recovery.md)
and [spec](../specs/portable-library-backup-and-recovery.md) are **provisional
drafts**. Their archive schema and generation-switch protocol must be revised
against a working prototype before planning creates a Ready issue.

## First question to answer

Can app and widget readers safely switch from one SwiftData store generation to
another while SwiftUI views, model contexts, and widget reads may still refer
to the old store? The current app creates one `ModelContainer` in
`flashcard_widgetApp.init`, and `SharedModelContainer.makeShared()` always opens
one fixed store path. Media currently lives in private Application Support.
This is the feasibility risk that should be tested before locking the archive
format or writing a full restore flow.

## First runnable slice

Use only a namespaced scratch library, never the live user library. Build two
small generations with clearly different deck content and an active-generation
pointer. Under the existing cross-process file lock, switch the pointer and
recreate app contexts; make widget code resolve the selected generation after
locking. Demonstrate an app view already open during the switch, a new widget
read afterward, and interruption immediately before and after pointer rename.
Verify that readers see one complete generation, stale contexts are replaced,
and the old generation remains available for recovery. Run focused tests and a
simulator/device trial where possible. This slice need not create a ZIP archive,
Files UI, or Reset Library control.

## Feedback and handoff

Show the user how the scratch switch behaves and any platform limitation. If a
live container cannot be swapped safely, test the smallest alternative, such
as a controlled app restart for restore, before choosing an architecture.
Record confirmed behavior, approaches tried, evidence, prototype commits,
checks, limitations, and remaining product choices in
`docs/explorations/portable-library-backup-and-recovery.md` when the direction
settles. Push the branch; planning can then revise the draft ADR/spec and create
a Ready issue. Exploration itself creates no Ready issue.
