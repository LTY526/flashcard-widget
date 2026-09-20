# active-card-deck-management

> Superseded for scheduling, pause/resume, and navigation behavior by
> [configurable-lock-screen-widget](configurable-lock-screen-widget.md) and
> ADR 0003. Back is removed, initial scheduling starts at injected `now`,
> and timestamps derive reached status while `sequence` remains strict order.
> [sleep-aware-schedule-and-four-field-display](sleep-aware-schedule-and-four-field-display.md)
> further supersedes it: initial state is one current plus ten future rows,
> automatic dates exclude sleep, setting edits rebuild future rows, and Schedule
> replaces History as the deck destination.

## Goal

Give every deck its own scheduled card queue (with projected timestamps),
its own Next/Back navigation, its own paginated history, its own
display-strategy config, and a per-deck pause/resume control — per
[0002](../decisions/0002-active-card-history-and-display-config.md). There
is no "which deck feeds the widget" concept in this spec: that only makes
sense once a widget extension exists to read it, which is out of scope
here.

## Acceptance criteria

### Deck Detail navigation

- [ ] Tapping a deck row in the deck list (`ContentView.swift`) navigates
      to that deck's Deck Detail screen (e.g. via `NavigationLink`) — no
      such per-row navigation or `DeckDetailView` exists today; every other
      "Deck Detail shows/lets the user..." criterion in this spec depends
      on this entry point existing.

### Pause / resume scheduling

- [ ] `Deck.isPaused: Bool` exists, defaulting to `false` — every deck
      schedules by default, and there is no limit on how many decks can be
      unpaused at once.
- [ ] The deck list (or Deck Detail) has a pause/resume control per deck
      (e.g. a toggle or swipe action), and the deck list shows which decks
      are currently paused (e.g. a visible label or dimmed state).
- [ ] While a deck is paused, no code path *regenerates* its queue —
      ordinary top-up, Next's cascade, an `order` change, and soft-delete
      reconciliation all skip regeneration for a paused deck. This is not
      absolute, though: the *discard* half of both the `order`-change and
      soft-delete reset primitive (see the reset section below) always
      runs, paused or not — discarding a stale or contaminated entry is a
      correctness fix, not accumulation, so both discards are exempt from
      the pause gate; only the regeneration each would otherwise trigger
      is skipped.
- [ ] Unpausing a deck resumes normal queue maintenance (see below) the
      next time that deck's schedule is read — including topping a
      short/empty queue (left short by a discard that ran while paused)
      back up to 10, using the same reference-entry rule as any other
      top-up (chain off the pointer's entry if non-`nil`, else the
      empty-queue rule) — this is the case a `highestReachedSequence`-based
      condition would get wrong, since a soft-delete-cleared pointer can
      leave `highestReachedSequence` non-`nil` while there's no entry left
      to chain off.
- [ ] An automated test pauses a deck with an existing queue, drives an
      action that would otherwise trigger a top-up or a Next, and asserts
      no `HistoryEntry` rows were added, removed, or re-timestamped; then
      unpauses it and asserts the queue tops back up on the next read.
- [ ] An automated test changes a paused deck's `order`, and separately, an
      automated test re-imports a fixture that soft-deletes a paused deck's
      current card — both assert the unreached queue is discarded (and, for
      the soft-delete case, the pointer cleared per the usual rule) but
      **not** regenerated while still paused; then, after unpausing,
      assert the queue tops back up to 10 on the next read.
- [ ] An automated test chains: pause a deck with history
      (`highestReachedSequence` non-`nil`) → re-import a fixture that
      soft-deletes its current card (pointer clears to `nil`, queue
      discarded, regeneration deferred since paused) → unpause → read the
      deck's schedule. Asserts the queue regenerates to 10 via the
      empty-queue rule (starting from the lowest-`ankiCardID` active card
      for `.sequential`) without crashing or misbehaving — this is
      specifically the case where `highestReachedSequence` is non-`nil`
      but the pointer is `nil` and the queue is empty, which a
      `highestReachedSequence`-keyed implementation would get wrong.

### Display config (one per deck)

- [ ] A `DisplayConfig` model exists with: `order` (`sequential` |
      `random`), `intervalMinutes` (Int), `newCardsADay` (Int),
      `reviewPreviousDayCards` (Bool), in a one-to-one relationship with
      `Deck` — not a list.
- [ ] Importing a `.apkg` that creates a brand-new `Deck` also creates that
      deck's one `DisplayConfig`, with defaults `order: .sequential`,
      `intervalMinutes: 30`, `newCardsADay: 0`, `reviewPreviousDayCards:
      false`. This must happen at every code path in `ApkgImporter` that
      constructs a new `Deck` (including its "Unknown Deck" fallback
      branch, not just the main upsert loop) — every deck must have exactly
      one config, with no exceptions. Re-importing into an already-existing
      deck does not create a second config.
- [ ] That deck's initial schedule (10 `HistoryEntry` rows, via the
      empty-queue generation rule below) is seeded once, later in the same
      import, after that deck's cards have been upserted — not at the
      `Deck`-creation site itself, which runs before any card exists for it
      to pick from. Both still happen inside the same import transaction,
      so a newly-created deck never leaves `ApkgImporter` without a config
      or without its initial queue. Re-importing into an already-existing
      deck does not reseed its schedule.
- [ ] An automated test imports a fixture that creates decks via both the
      main upsert loop and the "Unknown Deck" fallback branch, and asserts
      every resulting `Deck` has exactly one `DisplayConfig` and exactly 10
      `HistoryEntry` rows.
- [ ] An automated test re-imports the same fixture a second time and
      asserts each deck still has exactly one `DisplayConfig` (not two) and
      its schedule wasn't reseeded (the original 10 entries' identities are
      unchanged).
- [ ] `intervalMinutes` has a floor of 15 minutes: the edit UI (below)
      rejects or clamps lower values, and its copy states the value is
      advisory scheduling spacing, not a guaranteed exact interval.
- [ ] Deck Detail shows that deck's config and lets the user edit `order`,
      `intervalMinutes`, `newCardsADay`, and `reviewPreviousDayCards` in
      place, and the change is saved. There is no "add another config" or
      "switch which one is in use" UI — exactly one config always exists
      per deck.
- [ ] `newCardsADay` and `reviewPreviousDayCards` are stored and editable
      in this spec but have no runtime effect yet (no "new vs. reviewed"
      concept exists). `order` and `intervalMinutes` both have real effect,
      via the scheduled queue below.
- [ ] Editing `intervalMinutes` only changes the spacing used for entries
      generated *after* the edit — it does not retroactively alter
      `projectedAt` on entries already in the queue. (Editing `order`
      behaves differently — see the reset criterion below.)
- [ ] An automated test edits a deck's config fields (including `order`
      and `intervalMinutes`) and asserts the change is persisted.
- [ ] An automated test edits only `intervalMinutes` on a deck with an
      existing queue and asserts every already-queued entry's `projectedAt`
      is unchanged, while the next top-up-generated entry uses the new
      spacing.
- [ ] An automated test attempts to save an `intervalMinutes` value below
      15 and asserts it's rejected or clamped to 15.

### Per-deck scheduled queue, active card, and Next/Back

- [ ] A `HistoryEntry` model exists, scoped to one `Deck`: `card`,
      `sequence: Int` (monotonic, from a `Deck.nextHistorySequence`
      counter), and `projectedAt: Date` (the wall-clock time this entry
      becomes, or became, that deck's current card).
- [ ] `Deck` also has `activeHistoryEntry: HistoryEntry?` (the pointer) and
      `highestReachedSequence: Int?` (the highest `sequence` value Next has
      ever advanced to for that deck; `nil` if Next has never been tapped).
- [ ] **Queue maintenance ("top-up"):** whenever a non-paused deck's
      schedule is read (opening Deck Detail, the deck list, right after
      import, right after unpausing, as part of a Next/Back tap), ensure at
      least 10 `HistoryEntry` rows exist with `sequence >
      highestReachedSequence` (or, if `highestReachedSequence` is `nil`,
      at least 10 rows exist at all), generating more as needed. If the
      deck has zero active cards, there is nothing to generate — top-up
      is a no-op, and the deck simply stays below 10 (possibly at 0) until
      it has an active card again; this mirrors Next's zero-active-card
      handling below.
      - The reference entry to chain a new one off is found by checking,
        in order: (1) the entry with the highest `sequence` among all
        currently-unreached entries for the deck (`sequence >
        highestReachedSequence`) — regardless of whether that entry was
        generated just now, earlier in this same top-up call, or by an
        earlier, unrelated call entirely; (2) if no unreached entry exists
        at all, the pointer's own entry, **if the pointer is non-`nil`**;
        (3) if neither exists, there is no reference entry. Checking the
        actual current unreached queue first (not just "generated in this
        call") matters for the routine case — Next consumes one entry,
        top-up regenerates exactly one replacement — which must chain off
        the 9 entries the previous top-up already left in place, not off
        the pointer's now-stale, just-consumed entry; treating "nothing
        generated yet in this call" as "no reference entry" would
        silently repeat a card and collide a timestamp on every ordinary
        Next.
      - When a reference entry is found (case 1 or 2): `order: .sequential`
        picks the next active card after the reference entry's card by
        `ankiCardID`, wrapping to the first after the last; `order:
        .random` picks a random active card other than the reference
        entry's card, whenever the deck has more than one active card;
        `projectedAt` = the reference entry's `projectedAt` +
        `intervalMinutes`.
      - Case 3 — **no unreached entry and the pointer is `nil`** — is a
        deck that's never had a Next, or whose pointer was just cleared and
        its queue discarded: `order: .sequential` starts from the
        lowest-`ankiCardID` active card, `order: .random` has nothing to
        exclude, and `projectedAt` = now + `intervalMinutes`. This check is
        on the *pointer*, never on `highestReachedSequence`, which can be
        non-`nil` even though the pointer is `nil` and the queue is empty
        right after a soft-delete clear.
- [ ] **"Next" is a complete no-op while `Deck.isPaused` is `true`** — no
      entry is consumed, no `projectedAt` changes, the pointer and
      `highestReachedSequence` are untouched. This check happens before
      anything below, not just before the top-up/cascade portion of it.
      Otherwise, **"Next"** consumes the entry at `sequence ==
      highestReachedSequence + 1` (topping up one more first if it doesn't
      already exist): sets
      that entry's `projectedAt` to now, then shifts every later
      already-queued entry's `projectedAt` so each stays `intervalMinutes`
      apart from this new anchor, moves `activeHistoryEntry` to the
      consumed entry, sets `highestReachedSequence` to its `sequence`, and
      re-runs top-up. This is the same rule on a deck's very first Next
      (consuming the entry the initial top-up already generated) as on
      every subsequent one — there is no separate "generate because the
      pointer is at the tail" case.
- [ ] **"Back"** moves `activeHistoryEntry` to the entry with the
      next-lower `sequence`, changing nothing else (no new/deleted rows, no
      `projectedAt` or `highestReachedSequence` change). Disabled when the
      pointer is `nil` or already references the lowest-`sequence` entry
      that still exists for that deck.
- [ ] "Next" is disabled (or a no-op with no crash) when the deck has zero
      active cards.
- [ ] `HistoryEntry.card` is optional and nullify-on-delete, not a required
      cascade dependency — a `HistoryEntry` whose card has been deleted
      (see the deck-removal cross-deck note below) still exists and still
      shows in History, just with a "this card is no longer available"
      fallback in place of card text.
- [ ] Deck Detail shows the deck's current card (the pointer's entry's
      card's `primaryText`/`secondaryText`, per existing `Note` accessors)
      when the pointer references one and that entry's `card` is non-`nil`,
      and an empty state otherwise (fresh deck before its first Next, a
      pointer just cleared, or a pointer entry whose card became `nil`).
- [ ] Removing an *unrelated* deck can hard-delete a `Card` that this
      deck's `HistoryEntry` references, via `DeckRemover`'s existing
      cross-deck note cleanup (ADR 0001 decision 8) — this is expected, not
      a bug to prevent, and is exactly what the nullify-on-delete criterion
      above exists to handle gracefully.
- [ ] **Config `order` change:** discards every `HistoryEntry` with
      `sequence > highestReachedSequence` for that deck (the unreached
      queue only — the current entry and all of history are untouched).
      This discard always runs. Regeneration (10 fresh entries per the new
      `order`, using the same reference-entry rule as top-up above — chain
      off the pointer's entry, or the empty-queue rule if **the pointer**,
      not `highestReachedSequence`, is `nil`) runs immediately **only if
      the deck isn't paused**; if it is, the queue is simply left short
      and tops back up (per ordinary top-up, same reference-entry rule)
      once unpaused and next read.
- [ ] **Soft-delete reconciliation:** if a re-import soft-deletes any card
      belonging to a deck (ADR 0001 decision 6), that deck's entire
      unreached queue (`sequence > highestReachedSequence`) is discarded
      the same way as an `order` change, regardless of which specific
      queued entries referenced the removed card(s), **and regardless of
      whether the deck is paused** — this discard is a correctness fix
      (removing entries that reference a card that no longer exists), not
      an accumulation step, so pause never blocks it. If the pointer's own
      entry's card was among those soft-deleted, `activeHistoryEntry` is
      additionally cleared to `nil` — **without deleting that
      `HistoryEntry` row**, which remains visible in History. If the deck
      isn't paused, the queue is then regenerated back to 10 (via the
      empty-queue rule if the pointer is now `nil`, or chained off the
      still-valid current entry if it isn't), **synchronously, before that
      import call returns** — not deferred to whichever screen happens to
      read the deck next. If the deck is paused, the discard (and pointer
      clear, if applicable) still happens synchronously during the import,
      but regeneration is deferred until the deck is unpaused and read.
- [ ] An automated test drives Next repeatedly and asserts:
      `highestReachedSequence` only advances on a genuine Next, `sequence`
      values consumed are contiguous, and the cascade correctly re-spaces
      every later queued entry's `projectedAt` after each Next.
- [ ] An automated test asserts `.sequential` order visits every active
      card of a small fixture deck exactly once before repeating, in
      `ankiCardID` order.
- [ ] An automated test seeds a deck with a full 10-entry queue, taps Next
      once (consuming 1, leaving 9 pre-existing unreached entries), and
      asserts the single entry top-up generates to replace it chains off
      the highest-`sequence` entry among those 9 pre-existing ones — not
      off the pointer's just-consumed entry — with no repeated card and no
      colliding `projectedAt` against the existing 9.
- [ ] An automated test asserts `.random` order never repeats the
      immediately-previous card twice in a row for a deck with 2+ active
      cards, across a reasonable number of trials.
- [ ] An automated test asserts Back never changes
      `highestReachedSequence` and never creates or deletes rows, across
      several Back taps.
- [ ] An automated test drives Next on a deck with zero active cards and
      asserts no crash, no new `HistoryEntry`, and the pointer/
      `highestReachedSequence` unchanged.
- [ ] An automated test pauses a deck and drives Next, and asserts it's a
      complete no-op (no row created, no `projectedAt`/pointer/
      `highestReachedSequence` change) — distinct from the pause test in
      the previous section, this one specifically targets Next itself
      rather than read-time top-up.
- [ ] An automated test changes a deck's `order` and asserts: every entry
      with `sequence > highestReachedSequence` before the change is gone
      afterward, exactly 10 new entries exist following the new `order`,
      and the current entry plus all of history is unchanged.
- [ ] An automated test re-imports a fixture with one note (and its card)
      removed, where that card was the deck's current entry, and asserts:
      `activeHistoryEntry` is `nil` afterward, that `HistoryEntry` row
      still exists and still shows in History, the deck's unreached queue
      has been regenerated, and a subsequent Next consumes a freshly
      generated entry rather than any pre-existing one.
- [ ] An automated test re-imports a fixture that soft-deletes a card
      referenced only by an *unreached, queued* (not-yet-current)
      `HistoryEntry`, and asserts: the pointer is unaffected, every entry
      that was in the unreached queue before the import (including that
      contaminated one) is gone, and exactly 10 freshly generated entries
      exist afterward.

### Per-deck history screen

- [ ] Deck Detail links to a History screen scoped to that one deck,
      showing only `HistoryEntry` rows with `sequence <=
      highestReachedSequence` (never entries still sitting unreached in the
      queue) — card primary/secondary text plus `projectedAt` as the shown
      timestamp, or the "no longer available" fallback (above) for a row
      whose `card` is `nil`.
- [ ] Entries are sorted by `sequence` descending (most recent first).
- [ ] The list loads 10 entries at a time, loading the next 10 as the user
      scrolls near the end, rather than loading the entire history at once.
- [ ] An automated test seeds a deck with more history entries than fit in
      one page plus a full unreached queue ahead of them, and asserts: the
      first fetch returns exactly 10 (the 10 highest reached `sequence`
      values), a subsequent page fetch returns the next 10 (or fewer, if
      that's all that remain reached), and none of the unreached queue's
      entries ever appear.

### Deck removal cascade

- [ ] Removing a deck (existing `DeckRemover` flow) also deletes that
      deck's `DisplayConfig` and `HistoryEntry` rows as part of the same
      operation (via the `Deck` object graph — no separate cleanup pass
      needed for these two).
- [ ] An automated test removes a deck that has `DisplayConfig` and
      `HistoryEntry` rows (reached and unreached) and asserts all of them
      are gone afterward.
- [ ] An automated test sets up a note with cards in two decks (deck A's
      card soft-deleted, deck B's card active), where deck A's History
      references that shared note's card; removes deck B (whose removal
      erases the note per ADR 0001 decision 8, since deck A's card isn't
      active); and asserts deck A's `HistoryEntry` row still exists with
      `card == nil`, rather than being deleted or crashing.

## Scope-out

- Any "which deck feeds the widget" concept, a cap on how many decks can
  be unpaused, or anything a widget extension would configure — none of
  this has a real consumer until that extension exists, per
  [0001](../decisions/0001-anki-lockscreen-widget-architecture.md) and
  [0002](../decisions/0002-active-card-history-and-display-config.md).
- Any background timer, scheduled task, or process that keeps a deck's
  queue topped up while the app isn't open — queue maintenance in this
  spec only runs lazily, when something in the app touches a deck's
  schedule.
- Enforcing `newCardsADay` or `reviewPreviousDayCards` — the data model has
  no "new vs. reviewed" concept yet; these fields are stored and editable
  but inert.
- Multiple `DisplayConfig`s per deck, adding/removing configs, or an
  "in use" switch — each deck has exactly one config, editable in place
  (see [0002](../decisions/0002-active-card-history-and-display-config.md)
  alternatives).
- Any order strategy beyond `sequential` and `random`.
- The reusable `CardWidgetView` component and adopting it in Deck Detail's
  active-card display / `FieldMappingView` — separate spec
  ([reusable-card-view](reusable-card-view.md)); this spec's active-card
  display may use a simple inline layout in the interim.
- The actual WidgetKit extension target, and anything reading this deck's
  schedule from outside the main app process — separate future spec per
  [0001](../decisions/0001-anki-lockscreen-widget-architecture.md).
