# scalable-detailed-schedule-history

## Goal

Keep complete schedule history responsive and make every past card inspectable
without making the default list visually heavy.

## Dependencies and snapshot lifecycle

Build after `tabbed-deck-detail-and-simplified-config`; Schedule is one of its
three modes. A session begins on entry/re-entry to Schedule, explicit Refresh,
or successful foreground-activation reconciliation. These events reset the
watermark, rows, cursor, and expanded-row state together, while preserving the
selected Upcoming/Past subsection. Switching subsections and Load More in either
subsection do not start a new session. Current-card Next and configuration/pause
edits happen outside Schedule; returning to Schedule observes their saved results. If an
external save completes while Schedule remains visible, it does not silently
replace that session; explicit Refresh or the next activation/re-entry does.

This refines ADR 0004's visible-Schedule refresh rule: activation and re-entry
refresh data, but a clock tick, page append, or unrelated save does not move the
Past boundary underneath the reader. Upcoming and its horizon are captured in
the same session as the initial Past boundary. If activation reconciliation
fails, do not capture a new watermark or expose partially refreshed results;
retain the existing app activation error/retry gate.

## Acceptance criteria

- [ ] Past history is retained indefinitely; this feature performs no automatic
      history pruning or deletion.
- [ ] HistoryEntry sequence is treated as unique and immutable within one deck.
      The screen captures the successfully reconciled `highestReachedSequence`
      once when its snapshot session begins. Past eligibility for that session
      is `sequence < capturedWatermark`; a nil watermark produces no Past rows.
- [ ] The first Past request uses a SwiftData predicate scoped to the deck and
      captured watermark, sorts only by sequence descending, and has fetchLimit
      21: 20 displayed rows plus one look-ahead row that determines whether Load
      More is available. It does not traverse `deck.historyEntries`.
- [ ] Load More uses keyset pagination, adding `sequence < lowestLoadedSequence`
      to the same query and again fetching at most 21. It appends at most 20 and
      never uses a growing offset. Sequence identity guarantees no duplicates or
      gaps within the captured session regardless of equal projected dates.
- [ ] If schedule progress advances while the screen remains open, the captured
      watermark and loaded pages do not change except at the explicit session
      boundaries above. Refresh is an available user action. A new session
      captures newly reached entries and resets all paging/expansion state
      atomically, preserving Upcoming/Past selection.
- [ ] Page values are immutable and include sequence, projected date, and the
      primary, secondary, tertiary, and quaternary text read from the related
      card/note when that page is fetched. History is not an immutable text
      snapshot: later mapping/re-import edits are visible on a new fetch. A
      missing relationship produces the existing
      unavailable-card presentation rather than dropping the row.
- [ ] A collapsed Past row shows primary text and its stored projected date.
      Activating the row expands it in place to show every non-empty role in
      primary, secondary, tertiary, quaternary order. Expanded text is multiline
      and untruncated; activating it again collapses it.
- [ ] Expansion state is screen-local, does not change progress, and remains
      stable while another page is appended.
- [ ] Upcoming captures current plus the complete persisted future queue in the
      session, then displays 20 rows at a time with Load More. Paging Upcoming
      does not fetch or change the session. Its horizon uses the last future
      entry even when that row is not yet visible, displaying `Scheduled until
      <localized date and time>`, or a clear no-future-schedule message when
      appropriate.
- [ ] Opening and paging Past does not top up, reconcile, rebuild, save, or
      request a widget reload.
- [ ] Instrumented tests assert each Past page executes one bounded query with
      fetchLimit 21 and that requesting the first/next page does not fault or
      iterate the complete `deck.historyEntries` relationship.
- [ ] Scheduler, widget provider, and app-activation selectors operate from the
      pointer/watermark and bounded unreached queue; a test with several thousand
      past rows proves their selected result and bounded query shape do not vary
      with past-history count. Exercise full activation, immediate Next, and
      future-rebuild transactions, including deletion/application of queue changes,
      to prove none iterates or faults the complete history relationship. Query
      at most queueSize + 1 unreached rows (101 today) so oversized queues still
      fail validation rather than being silently truncated; fetch a current row
      by its pointer/sequence independently.
- [ ] Tests cover empty history, 1, 20, 21, and several hundred reached entries;
      stable page boundaries; missing relationships; all four display roles;
      expansion state; Upcoming paging and its schedule-horizon value; and session resets for
      activation/Refresh/re-entry versus stability for subsection changes,
      external saves, and Load More.

## Scope-out

- Deleting, searching, filtering, or exporting individual history entries.
- Automatic retention limits or pruning.
- Editing a card or jumping schedule progress from a history row.
