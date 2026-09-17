# sleep-aware-schedule-and-four-field-display

## Goal

Keep app and widget progress aligned after suspension, stop automatic card
progress during per-deck sleep hours, support three widget fields plus unlimited
in-app detail, and present past and upcoming cards together in a Schedule screen.

## Acceptance criteria

### App activation reconciliation

- [ ] On every transition to active, before deck content is interactive, the app
      acquires the exclusive schedule-mutation lock, creates a fresh disposable
      context after locking, and reconciles every unpaused deck using one injected
      `now`. It validates and computes every deck's plan before applying any
      mutation, applies the complete successful batch, saves exactly once,
      discards the context, refreshes the UI-visible models, and requests one
      debounced reload of widget kind `FlashcardWidget` when progress changed.
- [ ] Reopening after zero, one, or several entries became due immediately shows
      the same effective current card in Deck Detail as the provider selector;
      the old pre-suspension card is never briefly presented as current after
      reconciliation completes.
- [ ] Activation reconciliation is idempotent for the same `now`. A failure
      before or during planning applies no mutations. A failure while applying or
      saving rolls back and discards the disposable context; a newly opened
      context observes the unchanged pre-operation graph. No failed context or
      model instance is reused. The lock releases on every path and the app
      exposes the existing update failure UI instead of partial deck state.
- [ ] In-app Next uses the same injected `now`, reconciles first, advances once
      from the effective current entry, saves, and schedules one debounced widget
      reload. Tests cover a stale app pointer where the widget-effective card is
      two or more sequences ahead.

### Per-deck sleep configuration

- [ ] `DisplayConfig` persists `sleepEnabled`, `sleepStartMinute`, and
      `sleepEndMinute`, plus `scheduleTimeZoneIdentifier` recording the zone used
      for its current unreached queue. Minutes are integers in `0...1439`;
      defaults are disabled, 1320 (22:00), and 420 (07:00). When enabled, equal
      endpoints are rejected without changing persisted configuration.
- [ ] Deck Detail exposes a Sleep Schedule toggle and local-time start/end
      controls. The controls are per deck, remain editable while disabled, and
      clearly state that automatic progress stops during the range.
- [ ] The enabled sleep interval is the forward local-time range `[start, end)`;
      it may cross midnight. Start is asleep and end is awake. The calculation
      uses an injected `Calendar` and `TimeZone`; tests cover same-day and
      overnight ranges, exact boundaries, a daylight-saving transition, and a
      time-zone change.
- [ ] Local boundaries use `Calendar.nextDate`: nonexistent spring-forward times
      use matching policy `.nextTime`; repeated times use the first occurrence
      for sleep start and the last occurrence for sleep end. Tests assert exact
      resulting instants for both gap and overlap days.
- [ ] Boundary lookup uses these exact calls. Boundary components always include
      hour, minute, `second = 0`, and `nanosecond = 0`. Equality requires all four
      local components to match exactly; the supplied instant is never rounded.
      Thus 22:00:00 is exact start, 22:00:30 is inside sleep, 07:00:00 is exact
      wake, and 07:00:30 is thirty seconds after wake. For non-equal instants,
      the most recent start uses `nextDate(after: instant, matching:
      startComponents, matchingPolicy: .nextTime, repeatedTimePolicy: .first,
      direction: .backward)`. The next start uses the same policies with
      `.forward`. The paired end uses `nextDate(after: start,
      matching: endComponents, matchingPolicy: .nextTime,
      repeatedTimePolicy: .last, direction: .forward)` and must be strictly after
      start. Exact start is asleep; exact paired end is awake. Nil or non-forward
      results are typed schedule errors with no mutation. Tests cover exact,
      second-offset, and subsecond-offset start/end instants.
- [ ] A pure awake-time addition function accepts a date and positive duration.
      It consumes duration only outside sleep windows. Example: with sleep
      22:00–07:00, adding 30 minutes at 21:50 produces 07:20 the next morning;
      adding 30 minutes at 22:00 produces 07:30. Disabled sleep retains ordinary
      interval addition.
- [ ] Interval minutes convert to elapsed seconds with checked arithmetic; 30
      minutes means exactly 1,800 elapsed awake seconds on ordinary and DST days.
      Persisted `projectedAt` values are absolute UTC instants. Calendar matching
      is used only to locate local sleep boundaries.
- [ ] To find the sleep window relevant to an arbitrary instant, construct the
      most recent valid local start boundary at or before that instant using a
      backward search, then pair it with the first valid end boundary strictly
      after that start using a forward search. If the instant is in `[start,end)`,
      awake-time addition jumps to end. Otherwise it consumes elapsed seconds up
      to the next forward start, jumps to that start's paired end if duration
      remains, and repeats. If duration is exhausted exactly at sleep start, the
      result is the paired wake boundary rather than the asleep start instant.
      This algorithm handles both same-day and overnight ranges and is the sole
      sleep-membership calculation. A test proves 21:50 plus 10 awake minutes
      with 22:00–07:00 sleep returns exactly 07:00, not 22:00.
- [ ] With interval 30 minutes and sleep 00:00–08:00, a card current at 23:50
      has its successor due at exactly 08:20: ten minutes are consumed before
      sleep and the remaining twenty after wake.
- [ ] Initial seeding and resume make one explicit current entry at injected
      `now`, including when `now` is asleep. Reached rows made current by seed,
      resume, or manual Next may have sleep-window timestamps; unreached
      automatic rows may not. The first automatic successor is due one full
      awake interval after wake. Queue top-up, order changes, interval changes, sleep
      changes, and manual Next use the same awake-time addition function for all
      automatic successors; sequence order remains unchanged.
- [ ] Enabling or editing sleep settings preserves reached rows and the current
      pointer, discards only unreached rows, then regenerates ten unreached rows
      from injected `now` under the new settings. Whether `now` is awake or
      asleep, the first successor is one full awake interval after `now` (sleep
      portions excluded); it is never immediate and does not preserve remaining
      time from the pre-edit queue. The operation is one save followed by one
      debounced widget reload.
- [ ] On activation, compare the current time-zone identifier with
      `scheduleTimeZoneIdentifier` before reconciliation. If changed, preserve
      current/reached rows and watermark, discard every unreached old-zone row,
      regenerate ten successors from activation `now` using the new zone, store
      the new identifier, and then reconcile (which advances nothing newly
      generated). Tests prove an old-zone timestamp that is due in absolute time
      does not advance progress after travel.
- [ ] Initial seed, resume, and every future-queue rebuild set
      `scheduleTimeZoneIdentifier` to the injected zone identifier. When the zone
      changes and sleep is disabled, activation updates only this identifier and
      leaves absolute queue dates unchanged. When sleep is enabled, the rebuild
      rule above runs exactly once, preventing perpetual rebuilds.
- [ ] During sleep, activation reconciliation does not advance beyond the last
      entry due before sleep. At wake, elapsed awake-time dates reconcile
      normally; there is no overnight catch-up. Manual Next during sleep advances
      immediately and makes its successor due one full awake interval after wake.
- [ ] Every successful manual Next rewrites the newly current row's `projectedAt`
      to injected `now`, even inside sleep, updates the pointer/watermark, and
      reschedules every unreached successor through awake-time addition. Repeated
      manual Next actions may create multiple reached sleep-window timestamps,
      while every remaining unreached date stays outside sleep.
- [ ] The provider receives current plus at most four future sleep-adjusted
      entries. A deterministic provider test proves the sleep-spanning card stays
      visible until its shifted wake-side date.

### Four display roles

- [ ] `FieldRole` adds stable raw value `quaternary`. Existing primary,
      secondary, and tertiary raw values do not change. Mapping completeness
      still requires only at least one primary mapping.
- [ ] `Note` exposes `quaternaryText`, aggregating all quaternary-mapped fields in
      ordinal order using the same plain-text and ` / ` rules as other roles.
- [ ] Field Mapping offers Unused, Primary, Secondary, Tertiary, and Quaternary;
      its live sample reflects unsaved choices for all four roles. Existing
      mappings load unchanged.
- [ ] Plain Sendable card/timeline values carry primary, secondary, tertiary, and
      quaternary independently. Tests cover populated and nil values for every
      role.
- [ ] The `.accessoryRectangular` widget displays primary, secondary, and
      tertiary as exactly three compact single-line rows with tail truncation;
      primary may scale down to 0.75. Quaternary never appears in the widget.
      A nil secondary or tertiary occupies its row with a visible em dash so the
      layout remains three rows. Accessibility reads only non-nil role values in
      primary/secondary/tertiary order and does not announce the em dash.
- [ ] Deck Detail displays all four roles. Primary/secondary retain their current
      presentation; tertiary and quaternary have no line limit, use vertical
      fixed sizing, and expand the card to show their complete strings.
- [ ] Widget and mapping previews cover short values, long/truncated widget
      values, nil optional roles, and unlimited multiline tertiary/quaternary
      in-app values.

### Schedule screen

- [ ] Deck Detail replaces the History navigation row with `Schedule` and opens
      a deck-scoped Schedule screen with an Upcoming/Past segmented control. The
      screen remains blocked until foreground reconciliation has successfully
      committed and then queries only persisted progress.
- [ ] Upcoming is read-only and ordered ascending. Its first row is the current
      entry with a `Current` badge, followed by unreached scheduled entries with
      their local due date/time. It shows the complete persisted unreached queue
      (at most ten rows), has no pagination or Load More control, and never tops
      up or synthesizes entries while viewing. It has a clear empty state when no
      current or future entries exist.
- [ ] Past excludes the active current entry, includes only reached entries with
      lower sequence, is newest-first, and paginates ten rows at a time. Missing
      card relationships use the existing unavailable-card presentation rather
      than dropping the history row. An explicit `Load More` control fetches the
      next ten and disappears when no additional rows remain.
- [ ] Partitioning uses only the successfully reconciled persisted graph.
      `activeHistoryEntry` is the sole source of the Current badge and must match
      `highestReachedSequence`. Rows with sequence below the watermark are Past;
      rows above it are Upcoming. The current row itself is pinned in Upcoming so
      the user sees Current beside its successors. A valid nil pointer and nil
      watermark means every stored row is Upcoming without a badge. Any other
      nil/mismatched pointer-watermark combination shows broken schedule instead
      of deriving a virtual current or guessing. Past row dates are their stored
      `projectedAt` values; viewing never synthesizes reached state.
- [ ] Switching tabs never mutates the schedule, pointer, watermark, or queue.
      Tests verify partitioning has no duplicate row between tabs and no omitted
      reached/future row.
- [ ] After activation reconciliation, Next, pause/resume, or schedule-setting
      edits, an already-visible Schedule screen refreshes to the newly saved
      current/upcoming/past partition.

### Validation

- [ ] Existing pause behavior remains distinct from sleep: pause clears the
      unreached queue and shows `Deck paused`; sleep keeps the queue and shifts
      dates. Back remains absent.
- [ ] Existing schedule/deep-link/widget tests continue to pass, and new tests
      use injected clocks/calendars without wall-clock sleeps.
- [ ] The app and widget build for an iPhone simulator. A manual device checklist
      records: stale app card correcting on foreground, a card spanning sleep,
      manual Next during sleep, three widget rows, full in-app quaternary text,
      and correct Upcoming/Past partitions.
- [ ] ADR 0003, `docs/specs/configurable-lock-screen-widget.md`,
      `docs/specs/reusable-card-view.md`, and
      `docs/specs/active-card-deck-management.md` are updated or explicitly
      superseded where they still say tertiary is in-app-only, only three roles
      exist, History is the destination, or projected dates ignore sleep.

## Scope-out

- Different sleep ranges by weekday, calendar-date exceptions, holidays, or
  multiple sleep ranges in one day.
- Notifications, alarms, Focus integration, background timers, or proof that a
  scheduled card was actually seen.
- Editing, reordering, deleting, or jumping to cards from the Schedule screen.
- Quaternary text in the widget, more than three widget rows, images, audio, or
  widget families other than `.accessoryRectangular`.
- Changing the existing ten-entry persistent queue or five-entry WidgetKit
  timeline limits.

## Verifier objections (overruled by user)

REJECT. Two build-blocking contradictions/ambiguities in the sleep rules:

1) The spec declares sleep `[start,end)`, says sleep start is asleep, and
repeatedly requires that no unreached automatic entry may have a sleep-window
timestamp. But its awake-time addition algorithm can return exactly `start` when
the remaining duration equals the awake time up to the next start (e.g. sleep
22:00–07:00, add 10 min at 21:50). It says to jump only “if duration remains,”
so this yields 22:00—an explicitly asleep instant and forbidden automatic date.
The ADR makes the same categorical promise. It must state whether exact-start
completion returns start or wake; the latter seems consistent with the no-sleep
timestamp requirement, but changes the formal addition rule and needs an
acceptance test.

2) The mandated boundary lookup says to compare an instant’s local *hour/minute*
to the boundary and, on equality, return that instant. That incorrectly treats
any sub-minute instant such as 22:00:30 as the 22:00:00 sleep start (and similarly
07:00:45 as wake). `now` is injected as a Date and manual Next rewrites
`projectedAt` to arbitrary `now`, so second/fraction precision is plainly
possible. This can shift boundaries, membership, and awake-duration results.
Equality must be defined at an exact local boundary (including second/nanosecond
or explicit normalization), with sub-minute tests.

The user directed that both objections be fixed as specified and waived further
independent review.
