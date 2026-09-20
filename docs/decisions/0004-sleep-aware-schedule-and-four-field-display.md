# 0004: Sleep-aware schedules and four display roles

## Decision

1. Reconcile time-derived deck progress whenever the app becomes active, before
   presenting deck content. The app and widget use the same effective-current
   calculation, so reopening the app after several elapsed entries immediately
   shows the card already shown by the widget. In-app Next reconciles first and
   then advances exactly once.
2. Add an optional sleep range to each deck's `DisplayConfig`. It is stored as
   enabled/disabled plus local start and end minutes after midnight. The default
   is disabled, with 22:00–07:00 prefilled for convenience. Enabled endpoints
   must differ; the forward range from start to end may cross midnight.
3. Sleep ranges use the device's autoupdating calendar and time zone. Scheduled
   duration is counted only outside the sleep range. If an interval reaches the
   sleep start, its remaining duration resumes at wake time. The card current at
   sleep start therefore remains current throughout sleep, and later queue dates
   shift by the same excluded wall-clock duration. Sleep start is inside the
   range; wake time is outside it. Calendar calculations, rather than fixed
   seconds, define daily boundaries so daylight-saving changes do not invent or
   duplicate local times.
   For example, with a 30-minute interval and 00:00–08:00 sleep, a card that
   becomes current at 23:50 has a successor due at 08:20: ten awake minutes are
   consumed before sleep and twenty resume after wake.
4. Manual Next remains available during sleep. It makes the selected next card
   current immediately, then schedules its successor after one full amount of
   awake interval time; no automatic entry date is placed inside sleep.
5. Extend field mapping with an additive `quaternary` role. The widget displays
   primary, secondary, and tertiary as three compact rows. The app displays all
   four roles; tertiary and quaternary expand vertically without truncation.
   Mapping completeness continues to require only a primary field. This
   explicitly supersedes ADR 0003 decision 7 and its rejected-tertiary
   alternative, which kept tertiary in-app-only.
6. Replace the Deck Detail History destination with Schedule. Schedule has an
   Upcoming/Past segmented control. Upcoming shows the current card first with a
   Current badge, then unreached entries in ascending sequence/date order. Past
   excludes the current entry and shows earlier reached entries newest-first.
   Upcoming is read-only and shows the complete stored queue (at most 100 future
   rows), so it does not paginate or generate rows. Past is read-only and
   paginated ten rows at a time.
7. Editing interval, order, or sleep settings rebuilds only the unreached queue
   under the same exclusive mutation lock, preserves reached history/current,
   saves once, and requests the existing debounced widget reload.
8. A newly seeded/resumed deck still makes its first card current immediately,
   even when the user performs that action during sleep. Reached rows created by
   explicit seed, resume, or manual Next actions may have sleep-window
   timestamps, but no unreached automatic entry may. The first card's automatic
   successor is one full awake interval after wake. Rebuilding future entries
   after any setting edit preserves current/reached rows and schedules the first
   successor one full awake interval after the edit's injected `now`.
9. Persist the time-zone identifier used to generate each deck's queue. On app
   activation, a changed identifier is handled before ordinary reconciliation:
   preserve current/reached progress, discard the old-zone unreached queue, and
   regenerate successors from activation `now` in the new zone. Old-zone future
   timestamps never advance the watermark.
10. Learning intervals are elapsed awake seconds: 30 minutes means exactly
    1,800 seconds counted outside sleep. UTC instants remain the persisted
    representation; local calendar/time-zone rules are used only to locate sleep
    boundaries. Initial seed, resume, and rebuild store the generation zone.
    With sleep disabled, a zone change updates that metadata without rebuilding
    absolute queue dates. If awake duration is exhausted exactly at sleep start,
    the automatic due date is wake time, not the asleep start instant.
11. Foreground activation reconciliation is one exclusive-lock transaction. A
    fresh disposable context validates and plans every deck before applying any
    changes, saves the entire batch once, and is discarded on every failure.
    Schedule reads only the reconciled persisted pointer/watermark, never a
    virtual due-prefix projection.
12. The persistent look-ahead is 100 unreached entries per active deck; the
    WidgetKit timeline remains current plus at most four future entries. Deck
    Detail Next saves its pointer/watermark immediately, then debounces the
    100-row future rebuild for one second after the last tap. Leaving the view
    or starting another schedule mutation flushes the pending rebuild.

## Why

The database pointer can remain stale while the app is suspended even though
WidgetKit has moved through dated timeline entries. Reconciliation on activation
eliminates the misleading old card without requiring a render callback from
WidgetKit.

A sleep range is not a pause or a later catch-up. Counting only awake minutes
preserves every card in the sequence and lengthens the card that spans bedtime,
which matches the intent to stop learning progress overnight.

Three short widget rows use the rectangular Lock Screen space for the requested
supporting information. Moving the former in-app-only detail role to the widget
requires a new quaternary role so an unlimited in-app detail field remains
available.

History and future queue entries are two sides of the same ordered schedule.
One Schedule screen makes that relationship visible without allowing the list
to mutate progress.

## Alternatives considered

- Catch up every elapsed card at wake time — rejected because cards would
  progress during the range even though the widget deliberately did not show
  them.
- Restart the current card's full interval at wake time — rejected because it
  discards awake time already spent on the card before sleep.
- A global sleep range — rejected because different decks may be studied on
  different schedules.
- Keep tertiary in-app-only and omit a third widget row — rejected by the new
  display requirement.
- Mix past and future rows in one chronological list — rejected in favor of
  clearer Upcoming/Past tabs.

## Consequences

- Schedule date generation becomes calendar- and time-zone-aware and must use an
  injected calendar/time zone in deterministic tests.
- Changing time zone can change future local sleep boundaries; activation must
  validate and rebuild affected unreached dates without changing sequence.
- `FieldRole` and plain card-content values gain `quaternary`; existing stored
  raw values remain valid because the change is additive.
- The widget fits three single-line values, so long values still truncate and
  the full tertiary/quaternary content remains available in Deck Detail.
- The old History navigation label/view is replaced by Schedule, while existing
  reached `HistoryEntry` data remains intact.
- A nonexistent DST endpoint advances to the next valid local instant. For a
  repeated local endpoint, sleep start uses the first occurrence and sleep end
  uses the last occurrence, keeping the repeated hour inside sleep.
