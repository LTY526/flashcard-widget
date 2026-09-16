# 0003: Queue-driven configurable Lock Screen widget

## Decision

1. Add one WidgetKit extension supporting only `.accessoryRectangular`. It uses
   `AppIntentConfiguration` with an optional per-widget deck selection. The deck
   is an `AppEntity` identified by stable `Deck.ankiDeckID`; different widget
   instances may select different decks.
2. The app and widget share the complete SwiftData graph through App Group
   `group.com.xyz7172.flashcard-widget`, using one container factory and one
   explicit store URL. The project is pre-release, so existing development data
   is not migrated.
3. Scheduling is an ordered database queue. `sequence` remains the strict order.
   `projectedAt` says when an entry becomes reached/current. A newly seeded or
   regenerated empty schedule puts its first entry at the injected `now`, then
   spaces later entries by `intervalMinutes`. This supersedes ADR 0002's initial
   `now + intervalMinutes` rule and its statement that `projectedAt` is never
   compared; timestamps determine due status, never sequence order.
4. A read-only timeline selector finds the highest contiguous valid entry with
   `projectedAt <= now` as current, then sends that card plus at most the next
   four contiguous future entries to WidgetKit—five timeline entries maximum.
   The dates remain advisory; WidgetKit may display them late. Rendering a
   timeline entry has no callback and never mutates the database.
5. Reconciliation runs when the app becomes active and before an in-app Next
   action. On activation, the app reconciles every unpaused deck, including a
   deck that is not selected by an installed widget. Activation is one locked
   transaction: a fresh context validates and plans every unpaused deck before
   changing any,
   then applies all reconciliation/top-up plans and saves once. Any failure
   discards the whole context, so no selected deck commits partially.
   Reconciliation advances `highestReachedSequence` and `activeHistoryEntry`
   through the same contiguous due prefix and restores the queue to 10.
   The app records every reached entry as viewed/history based on its scheduled
   time; it does not try to prove the person looked at the Lock Screen.
6. Remove Back from the app and scheduler. Without a rewind state,
   `activeHistoryEntry` and `highestReachedSequence` identify the same entry
   after every successful reconciliation or Next operation. History remains
   newest-first and read-only.
7. The widget always shows primary and secondary together; tertiary stays
   in-app-only. The real `.accessoryRectangular` layout uses one line for each
   text value and has no interactive Next control. Card text is not marked
   privacy-sensitive; actual visibility remains controlled by system/user policy.
8. Next exists only in Deck Detail inside the app. Under the shared mutation
   lock, it first reconciles time-based progress, advances exactly once from the
   resulting effective current row, sets the advanced row's `projectedAt` to
   `now`, and reschedules every later queued row at `intervalMinutes` spacing
   from that anchor. It then tops up, saves once, and reloads WidgetKit. The
   widget itself is read-only and has no App Intent action.
9. Because the app and extension are separate processes, all store mutations
   that can race with scheduling use POSIX `flock` on
   `.schedule-mutation.lock` inside the App Group. Acquisition polls
   `LOCK_EX | LOCK_NB` every 50 milliseconds for at most 2 seconds, checks task
   cancellation between attempts, and returns a typed timeout/cancellation error
   without mutation if not acquired. Only after acquiring it, each operation creates a fresh disposable
   `ModelContext`, refetches by stable ID, performs the full mutation and one
   save, then discards the context before releasing the lock. Failed saves roll
   back and discard that context. Timeline, entity-query, and non-gallery
   snapshot reads acquire `LOCK_SH` with the same timeout/cancellation policy,
   create a fresh context after locking, fully materialize plain Sendable values
   before releasing, and never retain lazy model relationships outside the lock.
10. Tapping card content opens exactly
    `flashcard-widget://deck/<ankiDeckID>`, where `<ankiDeckID>` is canonical
    nonnegative `Int64` decimal: exactly `0` or a first digit 1–9 followed by
    digits, with no sign, leading zeros, whitespace, query, fragment, or extra
    path.
    The app opens that deck's detail for cold and warm launches; an invalid or
    deleted ID opens the deck list.
11. Widget state precedence is: store failure → `.failure`; no selection or
    deleted deck → `.chooseDeck`; incomplete mapping → `.needsMapping`; zero
    active cards → `.empty`; paused → `.paused`; invalid schedule →
    `.brokenSchedule`; otherwise → `.card`. Malformed reconciliation throws a
    typed schedule error before mutation, top-up, save, or reload; it never
    repairs or skips corruption. Failure retries after 15 minutes;
    other non-card states use `.never` and app mutations explicitly reload the
    widget.
12. Pausing a deck clears its entire unreached queue in the same locked save and
    requests a widget reload. A paused widget contains no queued card entries and
    renders `.paused`. Resuming seeds a new schedule whose first entry is at
    injected `now`, tops it up to 10, saves once, and reloads WidgetKit. Cards are
    not individually deleted; deleting a whole deck makes a configured widget
    render `.chooseDeck`.
13. Schedule validation is deliberately simple: fetch all unreached entries
    (`sequence > highestReachedSequence`, or all when nil). There must be at most
    10. Sorted rows must have unique consecutive sequences beginning at
    `(highestReachedSequence ?? 0) + 1`, valid active card/note relationships,
    and strictly increasing dates. Checked arithmetic is required for every
    increment/range; overflow is malformed, never a trap. A short valid queue may
    be topped up by a writer; any other violation fails without mutation.
    The reached base/current row must also belong to the deck, match the
    watermark, and resolve to an active card and note. Mapping completeness is
    classified only as `.needsMapping`, not `.brokenSchedule`. Otherwise the
    schedule state is `.brokenSchedule`.

## Why

WidgetKit is designed to receive future dated entries. Preparing an ordered
queue once and handing it five cards avoids trying to run a timer inside the
extension. The system changes the rendered entry near each date without needing
the app to be alive.

WidgetKit does not report that an entry was actually shown. Reconciliation does
not need such a callback: on the next app launch or interaction, timestamps
determine the contiguous prefix that was scheduled to have appeared. Calling it
"reached" accurately describes this inference without claiming the person saw
the screen.

Seeding the first entry at `now` removes the previous special case where an
unreached future card was displayed early. The timeline selector and mutation
reconciler now use exactly the same rule: contiguous entries at or before now
are reached; later entries are future.

Removing Back removes the competing pointer that caused earlier designs to
disagree about whether the app or widget was current. Time and the app's Next
button both move one monotonic watermark forward. History still lets the person
inspect earlier
cards without changing the schedule.

Per-instance App Intent configuration lets several widget instances select
different decks. A shared store is the single source of truth, while the App
Group lock—not SwiftData alone—serializes app writes against widget reads.

## Alternatives considered

- Notify the app whenever WidgetKit renders an entry — impossible because
  WidgetKit exposes no reliable displayed-entry callback.
- Keep Back — rejected because a rewound UI pointer conflicts with the monotonic
  timeline; History provides access to earlier cards without changing progress.
- Advance only through Next — rejected because the requested behavior is for
  cards to rotate automatically according to the configured interval.
- Maintain a separate widget cursor — rejected because app and widget could
  disagree and Next could jump backward.
- Show tertiary when space permits — rejected because Lock Screen space is
  constrained and tertiary is explicitly in-app detail.
- Support circular/inline families — deferred; they require different content
  rather than shrinking this layout.
- Use one globally selected deck or rotate all decks — rejected in favor of
  stable per-widget configuration.
- Assume one shared SwiftData store makes writes atomic — rejected; independent
  processes still require explicit mutation serialization.

## Consequences

- The app gains a WidgetKit extension, App Group entitlements, shared container
  infrastructure, configurable deck entities, and deck deep-link
  routing.
- Existing development data may be reset when the store moves; production
  migration remains a separate future decision if needed.
- Initial queue seeding changes to `projectedAt = now`, and all scheduling paths
  accept an injected clock. Existing ADR/code comments and tests are updated.
- Back UI, `DeckScheduler.back`, `DeckScheduler.canGoBack`, and their tests are
  removed. History data and pagination remain.
- The provider sends at most five entries even though the persisted queue stays
  topped up to 10.
- Automatic progress is inferred from scheduled dates and may overstate what a
  person actually saw, especially when WidgetKit delays delivery.
- App activation refreshes the main UI context after locked reconciliation of
  every unpaused deck before removing its loading overlay.
