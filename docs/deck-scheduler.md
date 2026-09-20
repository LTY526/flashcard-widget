# DeckScheduler

DeckScheduler owns the persisted order and timing of cards for each deck. The
app and widget do not independently invent a current card: both interpret the
same HistoryEntry graph in the shared SwiftData database.

## Persisted graph

Each deck has:

- activeHistoryEntry: the card currently shown by the app.
- highestReachedSequence: the sequence number of that current entry.
- nextHistorySequence: the next unused sequence number.
- Reached entries at or below the watermark.
- Unreached entries above the watermark.

An active, unpaused deck keeps **100 unreached entries**. The widget still
receives only the effective current card plus four future cards per timeline.
Past rows remain paginated 10 at a time.

~~~ts
type DeckSchedule = {
  current: HistoryEntry;
  highestReachedSequence: number;
  future: HistoryEntry[]; // contiguous sequences; target count is 100
};

function isFuture(entry: HistoryEntry, deck: DeckSchedule): boolean {
  return entry.sequence > deck.highestReachedSequence;
}
~~~

## Core invariants

1. Future sequences are unique, contiguous, and begin immediately after the
   watermark.
2. Future dates increase strictly.
3. Every scheduled card belongs to the deck and resolves to an active note.
4. The current pointer and watermark refer to the same sequence.
5. A paused deck has no future queue.
6. Automatic future dates never fall inside the sleep interval.

Invalid graphs are shown as a broken schedule instead of being guessed at.

## Initial seed and top-up

Seeding creates one real current entry at the injected time, then generates 100
automatic successors. Later top-ups append only enough entries to restore the
future queue to 100.

~~~ts
function topUp(deck: Deck, now: Date): void {
  if (deck.isPaused || deck.activeCards.length === 0) return;

  if (deck.hasNeverBeenSeeded) {
    deck.current = makeEntry({
      card: chooseInitialCard(deck),
      projectedAt: now,
      reached: true,
    });
  }

  while (deck.future.length < 100) {
    const previous = deck.future.at(-1) ?? deck.current;
    deck.future.push(makeEntry({
      card: chooseNextCard(previous.card, deck.order),
      projectedAt: addAwakeTime(previous.projectedAt, deck.interval),
      reached: false,
    }));
  }
}
~~~

Sequential order advances by Anki card ID and wraps at the end. Random order
chooses a random active card, avoiding an immediate repeat when possible.

## Foreground reconciliation

Dates can pass while the app is suspended. On activation, the app:

1. Acquires the exclusive schedule file lock.
2. Opens a fresh SwiftData context.
3. Uses one shared current time to plan every deck.
4. Finds the last contiguous future entry whose date is due.
5. Moves the pointer and watermark to that entry.
6. Restores each future queue to 100.
7. Applies every successful plan and saves once.
8. Refreshes visible app snapshots and requests a debounced widget reload.

Planning every deck before mutation makes the batch atomic.

~~~cs
using (ExclusiveScheduleLock.Acquire())
{
    var context = OpenFreshContext();
    var plans = decks.Select(deck => Plan(deck, now)).ToArray();

    // No model is mutated before every plan succeeds.
    foreach (var plan in plans)
        Apply(plan, context);

    context.SaveOnce();
}
~~~

## Manual Next and the one-second debounce

The visible card must react immediately when the user taps Next, but rebuilding
100 future rows on every rapid tap would block the button unnecessarily. Deck
Detail therefore performs Next in two phases.

### Immediate phase

- Reconcile already-due entries.
- Advance exactly one additional sequence.
- Rewrite the new current entry date to the tap time.
- Save the pointer and watermark immediately.
- Leave the remaining future dates alone temporarily.

### Deferred phase

- Wait one second after the most recent tap.
- Cancel and restart the wait when another tap arrives.
- Rebuild 100 future entries once, anchored at the final tap time.
- Save once and request the debounced widget reload.

~~~ts
function onNextTapped(now: Date): void {
  withExclusiveLock(() => {
    advanceCurrentImmediately(deck, now);
    save();
  });

  rebuildDebouncer.schedule({ delayMs: 1000, replacePending: true }, () => {
    withExclusiveLock(() => {
      rebuildFuture(deck, { anchor: now, count: 100 });
      save();
    });
    requestWidgetReload();
  });
}
~~~

Leaving Deck Detail, pausing or resuming, or editing schedule settings flushes
a pending rebuild immediately. Another screen or the widget therefore cannot
inherit the short-lived intermediate queue.

The non-UI next API remains synchronous for imports, tests, and other callers.
Only rapid Deck Detail taps use the split and debounced path.

## Sleep-aware dates

Intervals represent elapsed **awake** seconds. Sleep is a local-time range
[start, end), possibly crossing midnight. When an interval reaches sleep start,
calculation jumps to the paired wake boundary and continues afterward.

~~~ts
function addAwakeSeconds(start: Date, remaining: number): Date {
  let cursor = start;

  while (remaining > 0) {
    if (isInsideSleep(cursor)) {
      cursor = pairedWake(cursor);
      continue;
    }

    const nextSleep = nextSleepStart(cursor);
    const awakeUntilSleep = secondsBetween(cursor, nextSleep);

    if (remaining <= awakeUntilSleep) {
      const result = addSeconds(cursor, remaining);
      return result === nextSleep ? pairedWake(nextSleep) : result;
    }

    remaining -= awakeUntilSleep;
    cursor = pairedWake(nextSleep);
  }

  return cursor;
}
~~~

Calendar boundary searches use the recorded time-zone identifier. Nonexistent
spring-forward boundaries choose the next valid time; repeated fall-back sleep
starts use the first occurrence and wake boundaries use the last occurrence.

## Setting changes, pause, and time-zone changes

- Interval, order, and sleep edits preserve reached history/current, discard
  only future rows, and generate 100 successors from the edit time.
- Pause removes every future row.
- Resume creates a reached current row immediately and schedules 100 successors.
- With sleep enabled, travel rebuilds future rows in the new time zone before
  ordinary reconciliation.
- With sleep disabled, only the stored zone identifier changes; absolute future
  dates remain unchanged.

## Widget reads

The widget acquires a shared file lock and does not mutate the schedule. It
computes the effective current entry from the persisted pointer plus a
contiguous due prefix, then returns:

~~~ts
const widgetTimeline = [
  effectiveCurrent,
  ...futureAfter(effectiveCurrent).slice(0, 4),
];
~~~

The 100-entry database queue gives the widget a long unattended buffer, while a
five-entry WidgetKit timeline keeps extension work and payloads small.
