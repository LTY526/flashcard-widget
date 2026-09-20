# configurable-lock-screen-widget

> Superseded in part by
> [sleep-aware-schedule-and-four-field-display](sleep-aware-schedule-and-four-field-display.md):
> its sleep-aware dates, persisted initial current card, three widget rows, and
> Schedule screen requirements replace conflicting statements below.

## Goal

Add a per-instance configurable `.accessoryRectangular` Lock Screen widget that
reads five cards from each deck's ordered schedule, changes cards through a
WidgetKit timeline, and opens the configured deck's detail screen. Manual Next
remains available only inside the app.

## Acceptance criteria

### Target and shared store

- [ ] The project embeds one WidgetKit extension with bundle identifier
      `com.xyz7172.flashcard-widget.widget`, matching the app deployment target,
      and supports only `.accessoryRectangular`.
- [ ] App and widget targets have App Group
      `group.com.xyz7172.flashcard-widget` and use one shared factory for the
      complete SwiftData schema at an explicit group-container store URL. There
      is no fallback store. Existing development data need not be migrated.
- [ ] If the group container/store cannot open, the app shows
      `Unable to Open Library` with `Flashcards are unavailable. Please reopen
      the app.` instead of crashing; the widget returns `.failure`.
- [ ] A test writes a complete deck/card/config/history graph through a container
      at a temporary explicit URL, opens a second container at that URL, and
      verifies reads and subsequent saved mutations in both directions.

### Queue and time-derived progress

- [ ] Empty-schedule generation uses an injected `now`: sequence 1 has
      `projectedAt == now`; each following entry is exactly
      `intervalMinutes` later. Sequential/random card choice otherwise retains
      existing behavior, with randomness injectable in tests. Queue top-up
      remains 100 unreached entries.
- [ ] A plain read-only selector accepts a deck and injected `now`. If
      `highestReachedSequence` is nil, sequence 1 must be valid and due and is
      the base current. If it is non-nil, `activeHistoryEntry` must belong to the
      same deck, have exactly that sequence, and resolve to an active card/note;
      that row is the base current. Mapping completeness is checked separately
      and produces `.needsMapping`, never `.brokenSchedule`.
      The selector then starts at checked value `baseCurrent.sequence + 1` and
      examines consecutive rows, choosing the highest whose `projectedAt <= now`
      as effective current. A nil pointer with a non-nil watermark, a mismatched
      or cross-deck pointer, no due sequence 1 for a never-started active deck,
      or a nil/inactive/unrenderable base row returns `.brokenSchedule`. It then
      returns that entry followed by at most four consecutive entries with
      strictly later projected dates: five entries maximum, ordered by sequence
      and date. It never saves or changes a model.
- [ ] Before card-state selection or an unpaused scheduling mutation, fetch every
      unreached row for the deck—`sequence > highestReachedSequence`, or all rows
      when it is nil. More
      than 100 rows is malformed. After sorting, rows must be unique and exactly
      consecutive beginning at checked value `(highestReachedSequence ?? 0) +
      1`, with active card/note relationships and strictly increasing dates.
      Selection uses the effective current plus at most four rows from this
      already-validated queue. A short queue is valid; a writer tops it up and
      validates generated rows before one save.
- [ ] Every sequence increment/addition, including `nextHistorySequence` and
      timeline bounds, uses overflow-reporting
      arithmetic. Overflow returns `.brokenSchedule` for reads or throws
      `ScheduleError.malformed` for mutations without trapping or changing data.
      Tests seed `Int.max` boundaries.
- [ ] `intervalMinutes` is accepted only in the closed range `15...1440`.
      Schedule creation, reconciliation, and Next use checked conversion and
      date arithmetic; overflow or a non-finite result is malformed and causes
      no mutation.
- [ ] Reconciliation uses the identical contiguous due-prefix rule, advances
      `highestReachedSequence` and `activeHistoryEntry` to the same effective
      entry, tops the queue to 100, and saves the combined mutations exactly once.
      It never changes existing
      `projectedAt` values or moves progress backward. Running it twice with the
      same `now` is idempotent.
- [ ] If selection/reconciliation detects a malformed schedule, reconciliation
      throws `ScheduleError.malformed` before changing any object. It performs no
      top-up, save, repair, skip, or WidgetCenter reload. Tests compare complete
      pre/post graphs to prove the failure is mutation-free.
- [ ] Individual cards cannot be deleted. Deleting a deck removes the whole deck;
      a widget configured for that ID renders `.chooseDeck` and never falls back
      to another deck.
- [ ] Pausing a deck atomically removes every unreached queue row, preserves
      reached history, saves once, and reloads the widget. A paused deck has no
      queued timeline cards and renders `.paused`. Resuming atomically seeds a
      first entry at injected `now`, tops the queue up to 100, saves once, and
      reloads the widget. Tests cover pause and resume from populated and empty
      queues.
- [ ] When the app becomes active, it reconciles every unpaused deck, whether or
      not the deck is selected by an installed widget. Tests use injected time
      and cover decks with and without widgets.
- [ ] During activation work the app covers deck content with a blocking
      `ProgressView("Updating decks…")` and performs one exclusive-lock operation
      for the complete unpaused-deck set. In one fresh context it validates and
      computes every reconciliation/top-up plan without mutation; only if all
      plans succeed does it apply all plans and save exactly once. It then
      refetches/recreates the UI-visible model context before removing
      the overlay. A paused deck is unchanged. On
      malformed/store/lock failure it leaves persisted progress unchanged,
      removes the overlay, and presents an alert titled `Unable to Update Decks`
      with message `Your cards could not be updated. Please try again.` Tests use
      injected clocks—never sleeps—to cover zero, one, and multiple due entries,
      delayed app launch, idempotence, paused/empty decks, malformed queues, and
      top-up after several entries become reached.
- [ ] ADR 0002, `docs/specs/active-card-deck-management.md`, and source
      comments/tests are updated or explicitly superseded: Back is removed;
      initial scheduling uses `projectedAt = now`; `sequence` remains the
      strict order and timestamp tie-independent identity; `projectedAt` is now
      compared with `now` only to derive due/reached status.

### Back removal

- [ ] Deck Detail no longer shows Back. `DeckScheduler.back` and
      `DeckScheduler.canGoBack` are removed, along with tests specific to
      rewinding. No other control moves `activeHistoryEntry` or
      `highestReachedSequence` backward.
- [ ] History remains accessible, scoped per deck, newest-first and paginated as
      before. Removing Back does not delete existing history rows.

### Configuration and timeline

- [ ] The widget uses `AppIntentConfiguration` with optional `DeckEntity?`
      defaulting to nil. `DeckEntity.ID` is `ankiDeckID`; display representation
      uses the current deck name. Entity queries batch-resolve supplied IDs and
      suggest all decks, including paused decks.
- [ ] Two widget configurations can retain different deck IDs without a global
      active-deck property. Nil selection and a deleted selected deck never
      silently choose another deck.
- [ ] `timeline(for:in:)` opens the shared store read-only and converts selector
      results to plain Sendable entries containing only date, state, deck ID,
      and primary/secondary text. No SwiftData
      object crosses into the widget view.
- [ ] A card timeline contains at most five entries. Its first date is `now`
      with the effective current card; up to four future entries retain their
      original `projectedAt`. Dates are strictly increasing and no current/due
      card is duplicated. Reload policy is `.after(lastDate)` when future entries
      exist and `.after(now + intervalMinutes)` when only the current card exists.
- [ ] Placeholder and gallery snapshot use fixed sample data and never access or
      mutate the persistent store. A non-gallery snapshot resolves current state
      read-only.
- [ ] Provider tests cover initial card at now, exactly five available entries,
      fewer than five, several overdue cards, independent deck configurations,
      no duplicated/past-dated entries, and every non-card state/reload policy.

### Rendering and states

- [ ] State precedence is exactly: store failure → `.failure`; nil/deleted
      selection → `.chooseDeck`; incomplete field mapping → `.needsMapping`;
      zero active cards → `.empty`; paused → `.paused`; malformed schedule →
      `.brokenSchedule`; otherwise → `.card`. Once `.paused` is selected, the
      provider does not require or validate a queue.
- [ ] `.failure` reloads after 15 minutes. `.chooseDeck`, `.needsMapping`,
      `.empty`, `.paused`, and `.brokenSchedule` return one entry with `.never`;
      relevant app mutations explicitly reload this widget kind.
- [ ] Exact state text is: `Flashcards are unavailable`, `Choose a deck`,
      `Field mapping required`, `No cards in this deck`, `Deck paused`, and
      `Schedule unavailable — open the app` respectively.
- [ ] The real `.accessoryRectangular` view shows primary and secondary together
      and never tertiary. Each is one line with tail truncation; primary also has
      `minimumScaleFactor(0.75)`. Card text is not marked privacy-sensitive;
      actual visibility remains subject to system and user privacy policy.
- [ ] The widget contains no Next or Back button and no App Intent action. Card
      accessibility combines exactly as
      `Front: <primary>. Back: <secondary>.`; each state uses its visible text as
      its accessibility label.
- [ ] The app's mapping preview shares the widget layout/content component and
      continues showing tertiary separately as `In-app detail`. Widget previews
      cover short/long card text and every state in `.accessoryRectangular`.

### In-app Next and cross-process access

- [ ] A shared mutation coordinator uses an exclusive advisory lock file inside
      the App Group named `.schedule-mutation.lock`, implemented with POSIX
      `flock`. It attempts `LOCK_EX | LOCK_NB` every 50 milliseconds for at most
      2 seconds and checks cancellation between attempts; timeout throws
      `MutationLockError.timedOut`, cancellation throws `CancellationError`, and
      neither mutates. The lock covers the complete fetch–mutate–save section. App
      launch reconciliation, in-app Next, import, deck removal, mapping/config
      changes, and pause/resume all use it. The lock releases on all paths and is
      never held across unrelated UI/network work; timeline reads never mutate.
      Only after acquiring the lock, each mutation creates a fresh disposable
      `ModelContext`, refetches by stable ID, performs one transactional save,
      and discards the context before releasing the lock. No context created
      before lock acquisition is used to read or mutate locked state.
- [ ] Timeline, deck-entity-query, and non-gallery snapshot reads acquire
      `LOCK_SH | LOCK_NB` using the same polling, timeout, and cancellation
      behavior. After acquisition they create a fresh context, fully materialize
      plain values (including relationship-derived text) before unlocking, and
      never retain a SwiftData object/lazy relationship. Shared-lock failure
      returns `.failure`. Tests prove readers may coexist, exclude a writer, and
      observe one complete committed graph.
- [ ] Under the exclusive lock, the app's Next action first reconciles the due
      prefix through injected `now`, advances once from that effective current
      row, anchors the advanced row's `projectedAt` to `now`, reschedules every
      later row at the configured interval, tops up to 100, and saves once. Only
      after a successful save does it reload WidgetKit. A paused, deleted,
      empty, or missing-current deck is a no-op. Tests cover multiple overdue
      cards and ensure Next advances from the time-reconciled current card.
- [ ] Next tests assert the advanced row is anchored to injected `now`, every
      later row is cascaded at the configured interval without date collisions,
      and the next provider timeline reflects those new dates.

### Deep link and end-to-end validation

- [ ] Card content links to `flashcard-widget://deck/<ankiDeckID>`. The ID grammar
      is exactly `0` or `[1-9][0-9]*`, parsed as a nonnegative `Int64`. Negative
      or plus signs, leading zeros except the single value `0`, overflow past
      `Int64.max`, whitespace, query, fragment, trailing slash, or additional
      components are malformed. Canonical example:
      `flashcard-widget://deck/123456789`.
- [ ] The app registers the scheme and routes valid IDs to Deck Detail on cold
      and warm launch, replacing the current navigation path. Malformed,
      overflow, missing, or deleted IDs open the deck list. Parsing/resolution is
      plain logic with tests for every case.
- [ ] Import completion, mapping/config edits, pause/resume, and removal request
      a timeline reload after their successful locked save.
- [ ] The app, widget extension, and full Swift Testing suite build/pass for an
      iPhone simulator. Deterministic provider tests and Xcode widget timeline
      previews verify automatic entry ordering/transitions without asserting
      exact system delivery time. A recorded manual simulator checklist verifies
      that one rectangular widget can be added/configured, a second can select a
      different deck, in-app Next refreshes its widget, and card-content tap opens
      the correct Deck Detail; it does not gate success on waiting for an
      advisory scheduled transition.

## Scope-out

- Widget families other than `.accessoryRectangular`, Control Center controls,
  Live Activities, StandBy-specific layouts, and watch complications.
- A render callback or proof that the person saw a scheduled card; progress is
  inferred from time and called reached.
- Back or any other schedule rewind. History viewing remains available.
- Front/back reveal, tertiary, images, or audio in the widget.
- Exact WidgetKit delivery times, background timers, push updates, and more than
  five entries per supplied timeline.
- Global deck selection, automatic deck rotation, or automatic fallback decks.
- Production migration of the old app-only store.
- Enforcing `newCardsADay`, `reviewPreviousDayCards`, or spaced repetition.

## Verifier objections (overruled by user)

VERDICT: REJECT.

The core architecture is defensible (per-instance AppIntent configuration,
shared explicit SwiftData store, monotonic queue, advisory WidgetKit timelines,
and cross-process flock coordination), but the documents are not yet
unambiguous enough to build blind.

Blocking issues:

1. Reconciliation/history semantics are underspecified. ADR §5 says every
   reached entry is recorded as viewed/history using its scheduled time,
   including several overdue entries. The acceptance criteria only say to
   advance `highestReachedSequence` and `activeHistoryEntry` to the effective
   entry and mention `nextHistorySequence`; they never state whether new history
   rows are created for every traversed entry, what their timestamps/sequence
   values are, or how duplicates are prevented on retry. This affects
   idempotence, newest-first history, and complete-graph tests.
2. Next is undefined at the end of a short/empty unreached queue. It says
   reconcile, “advance exactly once,” reschedule later rows, then top up; but a
   short queue is valid and may contain zero rows after reconciliation. The
   later clause calls a “missing-current” deck a no-op, not a missing successor.
   Specify whether top-up occurs before advancing, or Next is a no-op, and what
   reload/save behavior results.
3. `intervalMinutes` invalidity has no read-state classification. The spec
   requires 15...1440 and mutations to throw malformed, but state
   precedence/selector rules do not say whether a persisted out-of-range
   interval yields `.brokenSchedule` (or another state), nor whether it is
   checked when paused/empty/needsMapping precede schedule validation.
4. “Empty-schedule generation” hardcodes sequence 1, while a valid previously
   reached deck with watermark N and zero unreached rows must top up from N+1.
   The intended initial-only meaning is inferable but not stated, and conflicts
   with the general phrase. Split initial seeding from post-history top-up and
   define both.
5. Failure atomicity language overclaims what is specified: “failed saves roll
   back” / complete pre-post graph equality requires an explicit
   transaction/rollback mechanism. A fresh context discarded after a failed
   SwiftData save does not itself specify or prove persistent-store atomicity.
   State the transaction contract/implementation or narrow the criterion to
   observable persisted state after reopening.
6. Checkability gaps: “reloads the widget” / “requests a timeline reload” needs
   an injectable reload client and exact widget kind to make deterministic tests
   possible; “save exactly once” likewise needs an observable test seam. The
   spec demands these tests but doesn’t require the seams.

Non-blocking but worth clarifying: define projected timestamps/history ordering
for multiple overdue entries explicitly; say whether URL interaction applies to
the whole rectangular widget (WidgetKit’s practical behavior), not merely “card
content”; and specify handling if entity-query shared-lock acquisition fails
(throw vs empty results).
