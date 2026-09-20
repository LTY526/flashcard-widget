# 0002: Per-deck active card, history, and display config

> Scheduling and navigation portions are superseded by ADR 0003. Back is
> removed; initial scheduling begins at injected `now`; sequence remains
> strict identity/order while timestamps are compared only for due status.
> Later widget work also supersedes this ADR's references to 10 queued entries:
> active decks now persist 100 future entries, while history still paginates 10
> rows at a time.

## Decision

1. **Active card and history are per-deck, not global.** Every `Deck` gets
   its own append-only `HistoryEntry` log and its own pointer to whichever
   entry is currently active for that deck. There is no single app-wide
   "active card" banner and no global History screen — each deck's own
   Deck Detail screen shows that deck's current card (with Next/Back) and
   links to that deck's own paginated History screen.
2. **Each deck can be paused or resumed independently, uncapped, with no
   "active deck" flag.** `Deck.isPaused: Bool` defaults `false` — every
   deck schedules by default, and any number of decks can be unpaused at
   once. There is no single "which deck feeds the widget" concept in this
   round at all: a future WidgetKit extension (out of scope here, per
   [0001](0001-anki-lockscreen-widget-architecture.md)) is what will
   eventually decide which deck(s) it reads from, via its own
   per-widget-instance configuration — nothing in this phase can stand in
   for that without inventing a rule with no real consumer. While
   `isPaused` is `true`, Next itself is a complete no-op — it does not
   consume an entry, does not move the pointer, does not touch
   `highestReachedSequence`, and does not set any `projectedAt` — not just
   "no refill/cascade" (decision 4 states this explicitly as a
   precondition on Next, not merely a side effect). Pausing does not
   delete or alter any existing `HistoryEntry` row, and scheduling resumes
   exactly where it left off once unpaused.
3. **A per-deck `DisplayConfig` model, one-to-one with `Deck`** — not a
   list the user manages. Fields: `order` (`sequential` | `random`),
   `intervalMinutes`, `newCardsADay`, `reviewPreviousDayCards`. It is
   auto-created the moment a deck is first created by import, with
   defaults `order: .sequential`, `intervalMinutes: 30`, `newCardsADay: 0`,
   `reviewPreviousDayCards: false` — the user is never shown a deck with
   no config, and `intervalMinutes`'s default is itself above the floor
   below, not just an example. The user edits its fields in place
   from Deck Detail; there is no "add another config" or "switch which one
   is in use" concept, since exactly one config always exists per deck.
   Multiple named configs per deck are a real possible future need, but
   deliberately deferred to keep this round's scheduling model simple —
   see Alternatives. `order` and `intervalMinutes` both have real
   behavioral effect this round (decision 4); `newCardsADay` and
   `reviewPreviousDayCards` are stored and editable but not yet enforced by
   any scheduler, since no "new vs. already reviewed" concept exists
   anywhere in the data model yet. `intervalMinutes` has a floor of 15
   minutes, enforced by the edit UI (matching ADR 0001's Consequences,
   which already called for this floor before this ADR existed), and the
   edit UI's copy must make clear the value is advisory scheduling
   spacing, not an exact countdown — same rationale as ADR 0001 decision 7.
4. **Each deck maintains a schedule, not just a log: `HistoryEntry` gains
   `projectedAt: Date`, and `Deck` gains `highestReachedSequence: Int?`.**
   `sequence` (as before, monotonic per-deck, from `Deck.nextHistorySequence`)
   remains the only thing "next"/"previous" logic is ever defined in terms
   of — never `projectedAt`, which stays purely informational (what a
   future widget's `TimelineProvider` would read) and is never compared for
   ordering, avoiding reintroducing the exact timestamp-collision hazard
   `sequence` was created to avoid in the first place.
   - **Queue maintenance ("top-up").** A deck that isn't paused and has at
     least one active card always has at least 10 `HistoryEntry` rows with
     `sequence > highestReachedSequence` (i.e., generated but not yet
     reached by Next). This is checked and topped up lazily, wherever a
     deck's schedule is touched (Deck Detail, the deck list, a Next/Back
     tap, right after import, right after unpausing) — there is no
     background timer or scheduled task in this phase; a deck left
     untouched for days simply tops up the next time something reads it.
     A deck with zero active cards has no entries to generate and stays at
     whatever count it already has (possibly zero) until it has an active
     card again.
   - **Generating one more queued entry** chains off "the reference
     entry," found by checking, in order: (1) the entry with the highest
     `sequence` among all currently-unreached entries for the deck
     (`sequence > highestReachedSequence`) — whether that entry was
     generated just now, earlier in this same top-up pass, or by a
     previous, unrelated call entirely, it makes no difference; (2) if no
     unreached entry exists at all, the pointer's own entry, if the
     pointer is non-`nil`; (3) if neither exists, there is no reference
     entry. Checking the *actual current unreached queue* first — rather
     than only entries generated within "this call" — matters because the
     routine case (Next consumes one entry, top-up regenerates exactly one
     replacement) must chain off the 9 entries the previous top-up already
     left in place, not off the pointer's now-stale, just-consumed entry;
     treating "nothing generated yet in this specific call" as equivalent
     to "no reference entry exists" would silently repeat a card and
     collide a timestamp on every ordinary Next.
     When a reference entry is found (case 1 or 2), `projectedAt` = that
     entry's `projectedAt` + `intervalMinutes`, and `order: .sequential`
     picks the next active card after its card by `ankiCardID` (wrapping
     to the first after the last), `order: .random` picks a random active
     card other than its card (whenever more than one active card exists).
     Case 3 — **no unreached entry and the pointer is `nil`** — is a
     deck that has never had a Next, or whose pointer was just cleared and
     its queue fully discarded (decision 5): there, `order: .sequential`
     starts from the lowest-`ankiCardID` active card, `order: .random` has
     no card to exclude, and `projectedAt` = now + `intervalMinutes`. Case
     3's pointer check is **never** substituted with "is
     `highestReachedSequence` `nil`" — the two are not equivalent: a
     pointer cleared by decision 6's soft-delete case leaves
     `highestReachedSequence` at its old, non-`nil` value while the
     pointer itself is `nil` and the queue is empty.
   - **`Deck.activeHistoryEntry: HistoryEntry?`** is the pointer, and it
     remains in exactly the same **two states** as before: references an
     entry belonging to the deck, or `nil`.
   - **"Next" is a no-op while the deck is paused** (decision 2) — check
     `isPaused` before anything below. Otherwise, **"Next"** always
     consumes the entry at `sequence == highestReachedSequence + 1`
     (topping up one more first if it doesn't already exist, which should
     only happen if top-up has fallen behind):
     sets that entry's `projectedAt` to now — collapsing whatever wait was
     left on it — cascades every entry after it in the queue so each stays
     `intervalMinutes` apart from this new anchor, moves the pointer to it,
     advances `highestReachedSequence` to match, then re-runs top-up. This
     is one rule for every case, including a deck's very first Next
     (`highestReachedSequence` is `nil`; the entry consumed is the one the
     initial top-up already generated via the empty-deck rule above) — there
     is no separate "mint fresh because the pointer is at the tail" branch,
     because the queue never actually runs dry while top-up keeps firing.
   - **"Back"** moves the pointer to the entry with the next-lower
     `sequence`, without creating, deleting, or re-timestamping anything —
     it never touches `highestReachedSequence`, since rewinding the user's
     own view isn't "unreaching" anything. Disabled when the pointer is
     `nil` or already at the lowest-`sequence` entry that still exists.
   - **History** shows entries with `sequence <= highestReachedSequence`
     (never entries still sitting unreached in the queue), sorted by
     `sequence` descending, 10 at a time.
5. **One reset primitive — "discard the unreached queue, then regenerate if
   not paused" — is triggered by two different events, never by a third.**
   The **discard** half always runs, even on a paused deck: leaving a
   stale or contaminated entry sitting in the queue is a correctness
   problem regardless of pause state. The **regenerate** half is gated by
   `isPaused` exactly like ordinary top-up (decision 4) — pausing means
   "stop refilling," and a reset's regeneration is refilling, not a
   one-time correctness fix, so it's subject to the same gate. A paused
   deck can end up with a short (even empty) unreached queue after either
   trigger; ordinary top-up brings it back to 10 the next time something
   reads that deck's schedule after it's unpaused, using whichever
   `order`/`intervalMinutes` are current at that time.
   - **Changing the deck's config `order`** discards every entry with
     `sequence > highestReachedSequence` (the queue only; the currently
     pointed-at entry and all real history are untouched), then, if the
     deck isn't paused, regenerates 10 fresh ones per the new `order`,
     using the reference-entry rule from decision 4 (chained off the
     pointer's entry, or via the empty-deck rule if **the pointer** is
     `nil` — not if `highestReachedSequence` is `nil`, per that same
     decision).
   - **A re-import soft-deleting any card belonging to that deck**
     (ADR 0001 decision 6) discards that deck's entire unreached queue the
     same way, and additionally, if the pointer's own entry's card was
     among those soft-deleted, clears the pointer to `nil` — **without
     deleting that `HistoryEntry` row**, which stays visible in History
     exactly as decision 4 already guarantees for every other entry. If
     the deck isn't paused, it's then regenerated using the same
     reference-entry rule (empty-deck rule if the pointer is now `nil`,
     chained off the still-valid pointer's entry if it isn't). Discarding
     the whole unreached queue on any
     soft-delete touching the deck — rather than trying to identify
     exactly which queued entries were individually contaminated — is
     deliberately the simple, safe superset: it's a handful of rows,
     regenerating them is cheap, and it avoids a second, harder
     bookkeeping problem of partial-queue repair. Unlike the general lazy
     top-up rule in decision 4, this specific discard-and-maybe-regenerate
     runs synchronously as part of the same import/save that performed the
     soft-delete, for every affected deck, paused or not — a touched
     non-paused deck never ends an import sitting below 10 queued entries
     waiting for some unrelated screen to notice; a touched paused deck's
     discard still runs synchronously, only the regeneration is deferred
     to whenever it's later unpaused and read.
6. **A reusable `CardWidgetView`** (primary text top, secondary text
   bottom, large rectangular card shape) is extracted and adopted by both
   each deck's active-card display and `FieldMappingView`'s existing
   sample preview, replacing their separately hand-rolled layouts. Its
   primary/placeholder/secondary/tertiary text selection logic is exposed
   as plain, directly testable functions (not just embedded in view body),
   since this project has no snapshot- or view-inspection-testing
   dependency today. This is a shared SwiftUI view, not a WidgetKit
   extension — no widget-extension target is created in this pass (per
   [0001](0001-anki-lockscreen-widget-architecture.md), which already
   flagged the real widget extension as its own future ADR/spec needing an
   App Group container and timeline provider not yet configured).
7. **`FieldRole` gains a `tertiary` case**, mappable from `FieldMappingView`
   alongside the existing `primary`/`secondary` options, and `Note` gains a
   `tertiaryText: String?` computed the same way as the existing
   `primaryText`/`secondaryText`. `CardWidgetView` takes tertiary text as a
   third, independently optional input, rendered below secondary when
   present. Tertiary exists specifically to hold additional detail that's
   useful when reviewing a card *inside the app* (Deck Detail's active-card
   display, `FieldMappingView`'s preview) but that a real Lock Screen
   widget won't have room to show — this is a presentation-space decision,
   not just "a third field slot," which is why it is a distinct role from
   `secondary` rather than "map more fields to secondary." No
   widget-extension-side suppression mechanism is built now, since no
   widget extension exists yet in this round; that future spec will decide
   whether/how to omit tertiary.

This ADR covers both halves as one architectural decision because they
share one data model, but is scoped into two specs so each is buildable and
reviewable independently: per-deck active card/history/config/scheduling
first, then the reusable view extraction.

## Why

**Per-deck state matches "each deck has its own progress."** A user
working through several decks wants each one to remember its own place —
switching decks shouldn't reset or share progress with another. Making
`HistoryEntry` and the active pointer properties of `Deck` itself, rather
than a single app-wide singleton, means removing a deck cascades its own
history away naturally (it's all one object graph) instead of requiring a
separate "did we just delete what the global pointer referenced" check.

**Pausing, not a single "active deck" flag, because nothing in this phase
actually reads "active."** An earlier draft of this ADR gave each deck a
user-toggled `isActiveDeck` flag meant to mark "which deck feeds the
widget." But the widget extension that would ever read that flag is
explicitly out of scope this round (per
[0001](0001-anki-lockscreen-widget-architecture.md)) — so the flag would
have no actual effect on anything the user can see, just a toggle for its
own sake. What this phase genuinely needs is a way to stop a deck's
schedule from accumulating entries the user doesn't care about right now,
which is exactly what an opt-out `isPaused` (default running) gives, without
pretending to model a widget-assignment concept that has no widget to
assign to yet. Leaving it uncapped (any number of decks can be unpaused) is
deliberate too: the real constraint — however many widget instances the
user can actually place — belongs entirely to the future widget-extension
spec, which will have an actual OS-level or design-level number to enforce
against. Modeling a cap now, before anything would violate it, would just
be guessing.

**An explicit `sequence` counter, never `projectedAt`, defines "next."**
Wall-clock timestamps can collide — two entries created in the same
millisecond are plausible both in an automated test loop and under real
device clock resolution — which would make "the next entry after this one"
ambiguous exactly when the pointer needs a strict answer. `projectedAt`
exists for an entirely different reader (a future widget's timeline), and
keeping the two concerns strictly separate means adding scheduling never
risks reopening the ordering-ambiguity problem `sequence` was introduced to
solve.

**The pointer keeps exactly two states, not three, for the same reason it
did before scheduling existed.** An earlier draft of this ADR left
ambiguous what a `nil` pointer should do when entries already exist ahead
of it — collapsing "empty log" and "pointer cleared" into one identical
`nil` state, with one unconditional rule, removed that ambiguity once, and
scheduling doesn't reopen it: the queue's pre-generated entries are never
"existing history to resume into" (nothing has pointed at them yet), so
consuming the next queued entry on Next is the same operation whether the
deck is brand new or was just cleared — there's still only one thing `nil`
ever means.

**Every "is there a reference entry to chain off" check is keyed on the
pointer, never on `highestReachedSequence`, because the two diverge exactly
when a pointer gets cleared.** A pointer cleared by decision 6's
soft-delete case leaves `highestReachedSequence` sitting at its old,
non-`nil` value — that deck has definitely reached entries before — while
the pointer itself is `nil` and its queue was just discarded down to zero.
An earlier draft of this ADR keyed queue generation's empty-deck rule off
"`highestReachedSequence` is `nil`," which is only true for a deck that has
literally never had a Next; it left generation undefined for a deck whose
pointer was cleared but which has real history behind it — exactly the
state a paused deck can sit in indefinitely between the clear and its next
unpause. The pointer is what actually determines whether there's a card to
chain off of, so it's the only condition every reset/top-up path checks.

**Next collapses the wait instead of merely being a preview, because the
in-app "current card" and the future widget's timeline need to describe the
same reality.** A version of Next that only changed which entry the app
*displays*, without touching any `projectedAt`, would let the app's current
card silently diverge from what a widget reading the same table at that
same real moment would show — defeating the reason for using real
timestamps at all. Cascading every later queued entry to stay
`intervalMinutes` apart from the new anchor, rather than leaving them at
their original times, keeps the schedule internally coherent after a manual
advance.

**Back stays free precisely because it doesn't touch `projectedAt` or
`highestReachedSequence`.** Rewinding the user's own view to an
already-reached entry doesn't change what's already happened — its
`projectedAt` is already safely in the past, and "how far this deck has
ever gotten" shouldn't shrink just because the user is peeking backward.

**`highestReachedSequence`, not the pointer's current position, is what
"has this deck ever shown this card" actually means.** Without a separate
high-water mark, History would have no way to tell a genuinely-reached
entry (belongs in History even after a Back, even after the pointer is
cleared to `nil`) apart from a purely speculative queued entry generated
ahead of time that nobody has ever seen (must never appear in History,
even once its `projectedAt` quietly slips into the past from a deck sitting
untouched for a while). Deriving this from timestamps instead — "has this
entry's `projectedAt` passed" — breaks exactly in that untouched-deck case,
since queued-but-never-reached entries can accumulate a past `projectedAt`
purely from the app not being opened, without ever having been shown to
anyone.

**One reset primitive, reused by two triggers, instead of two separate
ad-hoc behaviors.** Changing `order` and a re-import soft-deleting a card
both ultimately mean the same thing for scheduling purposes: "whatever was
queued ahead is no longer trustworthy, but real history and the currently
pointed-at entry are not." Defining "discard the unreached queue and
regenerate" once and triggering it from both places avoids writing (and
testing) the same logic twice with subtly different edge cases.

**Never deleting the pointer's own `HistoryEntry` row on a soft-delete
clear, even though the rest of the queue is discarded.** The row is real
history — the deck genuinely showed that card at some point — and decision
4 already guarantees every reached entry stays visible in History
regardless of what happens to the card it references later. Discarding
only the *unreached* queue preserves that guarantee while still cleaning up
the parts of the schedule that were never shown to anyone and might now be
stale.

**Discarding the *entire* unreached queue on any soft-delete touching the
deck, rather than picking out only the specific contaminated entries, is a
deliberate simplification.** A deck's queue is a handful of rows;
regenerating all of them is cheap. Identifying exactly which of the 10
queued entries reference a card that a given re-import just soft-deleted,
while leaving the rest of the queue's already-chosen `random` picks intact,
is a second, harder bookkeeping problem this phase doesn't need to solve to
get correct behavior.

**Sequential order needs a stable key, not insertion order into memory.**
Anki's own `ankiCardID`/import ordinal is stable across app relaunches and
future re-imports, whereas an in-memory array index is not.

**Random excludes the current card to feel like actual progress.** Anki
decks are frequently small (tens of cards) for a Lock Screen use case; a
naive `randomElement()` over the full active-card set would visibly repeat
the same card back-to-back a meaningful fraction of the time. Excluding the
current card (when more than one exists) avoids that without implementing a
larger no-repeat-window scheme, which isn't asked for here.

**Deferring `newCardsADay`/`reviewPreviousDayCards` enforcement is a scope
decision, not an oversight.** Enforcing them needs a "new vs. already
reviewed" concept that doesn't exist anywhere in the data model yet.
Storing the fields now avoids a second `DisplayConfig` migration once that
concept exists, without guessing at its shape today. `intervalMinutes`, by
contrast, is enforced this round, because it's exactly the number the
scheduling queue above needs to space entries apart — there's no separate
engine to build for it the way there would be for the other two.

**The reusable view's text-selection logic is exposed as plain functions
because there's no view-testing tooling in this project yet.** Adding a
snapshot- or view-inspection-testing dependency is a real decision with its
own tradeoffs (build time, a new SPM dependency) that this spec doesn't
need to make just to verify "given nil primary, show the placeholder
string" — that's testable as ordinary logic if it isn't buried inside a
`body` computed property.

**No WidgetKit extension target yet, by explicit choice.** Standing up a
real widget extension needs an App Group container shared with the main
app's `ModelContainer` (per ADR 0001's consequences, not yet configured), a
`TimelineProvider`, and a widget configuration — none of which this round's
scope (a reusable SwiftUI view for in-app preview, and a scheduling data
model shaped so that future `TimelineProvider` can read it directly)
requires building yet.

**No background timer or scheduled task in the main app, by the same
choice.** The lazy "top up whenever touched" approach is sufficient until a
widget extension exists — at that point, WidgetKit's own periodic timeline
reloads become the mechanism that keeps a deck's schedule fresh even while
the main app isn't open, and this phase doesn't need to build a
stand-in for that job just to have *something* running in the meantime.

**Tertiary is a distinct role, not "more secondary," because it encodes a
presentation-space decision, not just more content.** Fields already
mapped to `secondary` are joined together and always shown wherever
`CardWidgetView` renders at all — including a future, actual Lock Screen
widget with real space constraints. Tertiary is specifically for detail
that's fine to show inside the app (where there's plenty of room — Deck
Detail's active-card display, `FieldMappingView`'s preview) but that
wouldn't fit a real widget. Keeping it a separate role means a future
widget-extension spec can mechanically decide "don't render tertiary"
without having to guess which of a deck's mapped fields were "meant for"
the widget versus the app — that information is captured in the mapping
itself, at the time the user makes it, rather than reconstructed later.

## Alternatives considered

- **A single global active-card/history model** (this ADR's first draft) —
  rejected: doesn't match "each deck has its own progress," and required a
  separate check for "did deck removal just orphan the global pointer,"
  which per-deck scoping avoids by construction.
- **Keep a user-toggled `isActiveDeck` flag marking one deck for the
  (future) widget** (this ADR's first and second drafts) — rejected: no
  widget extension exists yet in this round to ever read it, so it would be
  a control with no observable effect, and the "at most one" invariant it
  would need to enforce (plus reassignment logic on deck removal) is real
  complexity for a concept with nothing consuming it yet.
- **Cap the number of concurrently-unpaused decks (e.g. at 2, matching
  anticipated Lock Screen widget capacity)** — rejected for now: no widget
  exists yet to actually be limited by this, so enforcing a cap in the main
  app would be modeling a constraint against a consumer that doesn't exist,
  based on a number ("2") that belongs to the future widget-extension spec
  to actually decide and enforce.
- **Auto-select which decks run (e.g. the first N by creation order), with
  no user control at all** — rejected in favor of `isPaused`: some per-deck
  control is still useful so the user can stop a deck's schedule from
  accumulating entries they don't care about; an explicit opt-out default-on
  flag is simpler than an auto-selection rule that would need its own
  tie-break logic for no real benefit.
- **Derive "next"/"tail" from `projectedAt` (or, before scheduling existed,
  `shownAt`) instead of an explicit `sequence`** — rejected: wall-clock
  timestamps can tie under coarse clock resolution or rapid, same-tick
  generation, making ordering ambiguous exactly where the logic needs a
  strict answer; `sequence` has no such ambiguity, and keeping `projectedAt`
  purely informational avoids reintroducing the hazard in a second place.
- **"Back" logs a new History entry for the previous card** — rejected:
  turns casual back/forward browsing into log noise.
- **Let a pointer cleared by soft-delete "resume forward" through
  already-queued entries, instead of always regenerating the queue** — an
  earlier draft rejected this even before scheduling existed, for the same
  reason it's still rejected now: resuming would silently walk the user
  forward through entries they never consciously navigated to.
- **Leave a soft-deleted active card displayed until the user next taps
  Next** — rejected: silently shows the user a card the app just
  determined no longer exists in their deck.
- **Make Next a pure preview that never mutates `projectedAt`** — rejected:
  this was the first design considered for schedule-aware Next, but it
  would let the app's displayed "current card" diverge from what a future
  widget reading the same table at that real moment would actually show,
  defeating the point of using real timestamps.
- **Regenerate the entire future queue from scratch on every Next, instead
  of cascading the existing rows' `projectedAt`** — rejected: more
  expensive than shifting timestamps on rows that already exist, and it
  would re-roll already-chosen `random` picks the user hasn't even reached
  yet for no behavioral gain.
- **Delete and regenerate only the specific queued entries whose card was
  soft-deleted, instead of discarding the whole unreached queue** —
  rejected: correctly identifying which of the queue's entries are
  contaminated, while preserving the rest exactly as generated, is a harder
  bookkeeping problem than just discarding a handful of never-shown rows and
  regenerating them.
- **Track "has this entry been shown" via `projectedAt` alone (e.g. "shown
  if `projectedAt <= now`") instead of an explicit `highestReachedSequence`**
  — rejected: breaks for a deck left untouched for a while, where queued
  (never-reached) entries can accumulate a past `projectedAt` purely from
  time passing, which would make them incorrectly appear in History despite
  never having been shown to anyone.
- **Maintain the schedule with a background timer or task in the main app**
  — deferred: no scheduling infrastructure exists in this app yet; lazy
  top-up whenever a screen touches the deck is sufficient until the future
  widget extension's own periodic timeline reloads take over that job.
- **Enforce `newCardsADay`/`reviewPreviousDayCards` in this pass** —
  deferred: needs a new/reviewed distinction the data model doesn't have.
- **Multiple named `DisplayConfig`s per deck, with an "in use" switch**
  (this ADR's first draft) — deferred, not rejected outright: real added
  complexity for a use case nobody has asked for yet. A one-to-one config
  keeps this round's scheduling model simple; revisit if a genuine need for
  multiple presets per deck surfaces.
- **Build the WidgetKit extension target in this same pass** — deferred to
  a future ADR/spec, matching ADR 0001's original plan.
- **Add a snapshot/view-inspection testing dependency to verify
  `CardWidgetView`** — deferred: exposing its text-selection logic as plain
  functions covers the testable behavior without a new dependency; revisit
  if a future spec needs true pixel/layout verification.
- **Map additional fields to `secondary` instead of adding a `tertiary`
  role** — rejected: `secondary` is shown wherever `CardWidgetView` renders
  at all, including a future real widget; there would be no way for a
  future widget-extension spec to mechanically exclude "the extra detail"
  from what it renders without redefining what `secondary` means at that
  point.
- **Change `DeckRemover`'s "active card elsewhere" check to also treat a
  card referenced by another deck's `HistoryEntry` as active, so it's never
  cascade-deleted out from under that deck's History** — rejected: that
  check is ADR 0001 decision 8's, defined in terms of live card/note
  sharing across decks; coupling it to a new per-deck feature's HistoryEntry
  table adds cross-module knowledge for a rare edge case that a simple
  nullify-and-fallback on the `HistoryEntry` side already handles without
  touching decision 8 at all.

## Consequences

- `flashcard_widgetApp.swift`'s `Schema` array must add `DisplayConfig` and
  `HistoryEntry` — a real SwiftData migration on top of existing installs
  (currently unreleased/dev-only, so no migration plan beyond adding the
  models is needed yet).
- `Deck` gains `historyEntries: [HistoryEntry]` (cascade-deleted with the
  deck), `activeHistoryEntry: HistoryEntry?`, `nextHistorySequence: Int`,
  `highestReachedSequence: Int?`, and `isPaused: Bool`; removing a deck
  deletes its own history and config as one object graph, with no separate
  cleanup pass needed.
- `HistoryEntry` gains `projectedAt: Date` alongside its existing `card` and
  `sequence`; its `card` relationship must be optional/nullify-on-delete,
  not a required cascade dependency (see the cross-deck note below) — a
  `HistoryEntry` whose `card` has become `nil` still exists and still shows
  in History, just without card text to render.
- `ApkgImporter` creates each `Deck` and its `DisplayConfig` at the same two
  sites as today, but seeding that deck's first 10 `HistoryEntry` rows via
  the empty-deck generation rule cannot happen at that point — the deck has
  no cards yet at either creation site (cards are only upserted afterward,
  in `apply`'s later loop). Seeding must happen once per newly-created deck
  after that deck's cards exist, later in the same `apply` call, still
  inside the same transaction/`save()`.
- `ApkgImporter`'s reconciliation path (soft-deleting notes/cards absent
  from a re-imported file) must, for each affected deck: discard every
  `HistoryEntry` with `sequence > highestReachedSequence`, and if the
  pointer's own entry's card was among those soft-deleted, clear
  `activeHistoryEntry` to `nil` (without deleting that row) — then
  regenerate that deck's queue back to 10, synchronously, before `apply`
  returns (not deferred to whatever next happens to read the deck).
- Any code path that reads a deck's schedule (Deck Detail, deck list, the
  History screen, Next/Back) must still be prepared to run the top-up check
  as part of that read, since no background process does this instead —
  the synchronous regeneration above only guarantees a touched deck leaves
  `ApkgImporter` at 10; a deck that's never re-imported still relies on
  read-time top-up entirely.
- `DeckRemover`'s existing cross-deck cleanup (erasing a note, and cascading
  its cards, when none of the note's cards are active outside the deck
  being removed — ADR 0001 decision 8) can delete a `Card` that an
  unrelated, untouched deck's `HistoryEntry` references, if that other
  deck's reference is to a card already soft-deleted rather than active.
  `HistoryEntry.card` being nullify-on-delete (above) means this leaves a
  `nil`-carded History row instead of an inconsistent or crashing one;
  the History screen and Deck Detail's active-card display must render a
  "this card is no longer available" fallback when `card` is `nil`, for
  both a soft-delete-cleared current entry and this cross-deck case.
- `intervalMinutes` needs a 15-minute floor enforced in the `DisplayConfig`
  edit UI, and copy explaining it's advisory scheduling spacing, not a
  literal countdown — carried over from ADR 0001's Consequences, which
  already specified this floor before this ADR existed.
- `FieldRole` gains a `tertiary` case; `Note` gains `tertiaryText: String?`
  alongside the existing `primaryText`/`secondaryText`; `FieldMappingView`'s
  per-field picker gains a "Tertiary" option and its live preview must feed
  tertiary through the same in-progress-selection mechanism it already uses
  for primary/secondary.
- The per-deck active-card display and `FieldMappingView`'s preview both
  take on a dependency on the new `CardWidgetView`; its parameters must be
  generic (primary/secondary/tertiary strings, not a specific model type)
  so a future WidgetKit extension can reuse it (omitting tertiary) without
  depending on live SwiftData objects across the App Group boundary.
