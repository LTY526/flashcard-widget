# tabbed-deck-detail-and-simplified-config

## Goal

Organize Deck Detail around Current, Schedule, and Config while removing settings
that have no scheduling effect.

## Codebase baseline

The existing UI and schema are at `7f7df1d`.
`DeckDetailView.swift` owns the one-second Next debounce and currently swallows
flush errors after clearing its pending anchor. `DeckHistoryView.swift` loads a
value snapshot; preserving its tab must not accidentally preserve stale data.
`DeckDeepLink.swift` parses widget URLs, but root URL routing and scheme
registration must also be wired for end-to-end navigation.

## Acceptance criteria

- [ ] Deck Detail presents exactly three clearly labelled modes: Current,
      Schedule, and Config. Opening a deck normally defaults to Current.
- [ ] Current contains the complete four-role current-card presentation, Next,
      and pause/resume behavior. It does not duplicate schedule/config controls.
- [ ] Schedule contains the Upcoming/Past interface and preserves its selected
      subsection while the Deck Detail instance remains alive. Entering Schedule
      loads the latest saved state after pending work succeeds. A subsection
      selection is UI state, independent of a data snapshot's lifetime.
- [ ] Config contains order, interval, sleep schedule, and field-mapping access.
      Every shown setting has an implemented effect.
- [ ] A widget deep link opens the matching Deck Detail on Current, including
      when that deck was previously open on another mode. Include URL scheme
      registration and root navigation routing, following the existing
      `configurable-lock-screen-widget` contract for cold/warm launch and
      invalid or missing deck IDs. Do not duplicate a detail route already open
      for that deck; reset its mode to Current.
- [ ] Switching away from Current or leaving Deck Detail flushes any pending
      debounced Next rebuild. A root-owned coordinator retains each pending
      deck ID and rebuild anchor until its locked rebuild and save succeed;
      canceling the timer or destroying the detail view never discards the work.
      Only successful save clears pending work and requests the widget reload.
- [ ] On flush/lock/save failure, surface a retryable error, preserve the pending
      anchor, and stop the dependent schedule mutation for every affected deck
      (including Next, pause, config, and shared field-mapping mutations). A mode
      switch stays on Current until retry succeeds. If system navigation has
      already left Detail, the root coordinator still owns the work, exposes
      Retry there, and gates later mutations until it succeeds. Activation and
      other app mutation entry points use the same coordinator before changing
      an affected schedule. Successful retry rebuilds exactly once; leaving the
      screen never triggers a second timer-driven rebuild.
- [ ] `newCardsADay` and `reviewPreviousDayCards` controls, model properties,
      initializer parameters, obsolete behavior assertions, and current usage
      guidance are removed. Historical ADR/spec records and explicitly named
      pre-change migration fixtures may retain the old names as evidence.
- [ ] An existing on-device store created by the previous schema opens without
      data loss. Decks retain order, interval, sleep configuration, mappings,
      history, current pointer, and future queue after migration. Keep an on-disk
      fixture generated with the complete `7f7df1d` schema, open it through the
      production container factory using the new schema, then save/reopen and
      compare retained values and relationships. Do not substitute a newly
      created in-memory store for migration evidence; add an explicit migration
      plan only if the verified schema transition requires one.
- [ ] Mode selection has an explicit accessibility label/value, works with
      VoiceOver, and remains operable at accessibility Dynamic Type sizes.
- [ ] Tests cover initial mode, deep-link mode reset, subsection preservation,
      pending-Next flush and injected lock/save failures (including navigation
      away and retry), fresh Schedule entry, configuration placement, and
      old-store migration.

## Scope-out

- New scheduling rules replacing the removed unused options.
- Deck search/sort, bulk operations, or navigation redesign outside Deck Detail.
- Widget presentation preferences.
