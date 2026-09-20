# Widget timeline

[Documentation index](../README.md) | [DeckScheduler](../deck-scheduler.md)

The widget is a read-only projection of a deck schedule. WidgetKit decides when
to launch the extension and when to render entries already returned to it.

## Configuration

DeckEntity and DeckEntityQuery expose available decks to the configurable
widget intent. The query opens the App Group store under a shared lock. Entity
IDs are persistent deck IDs, so a saved widget remains associated across app
launches. A deleted deck resolves to an unavailable state.

## Provider pipeline

1. Resolve the selected deck.
2. Acquire the shared schedule lock.
3. Open a fresh shared ModelContext.
4. Ask ScheduleSelector for plain timeline values.
5. Return the effective current entry and at most four future entries.

The persistent schedule contains up to 100 future cards. The widget batch is
only five entries total because WidgetKit timelines should stay small and can
be refreshed before the full persistent queue is exhausted.

## States

| State | Meaning |
|---|---|
| Ready | Selected deck has displayable scheduled content |
| No deck selected | User must configure the widget |
| Empty | Deck has no usable cards/schedule |
| Paused | Pausing cleared the queue; no card should advance |
| Unavailable | Shared store, lock, or selected deck could not be resolved |

## Rendering

The widget lays out primary, secondary, and tertiary values as three
left-aligned rows. Quaternary content is app-only. Tapping the widget opens the
deck detail through flashcard-widget://deck/<persistent-id>.

## Reload behavior

WidgetTimelineReloader coalesces repeated reload requests. Rapid Next taps
therefore cause one request after the app finishes its debounced schedule
rebuild. Imports, pause/resume, settings changes, and activation reconciliation
also request a reload when their saved state changes.

A reload request is not a synchronous redraw. WidgetKit controls launch timing
and may display an already-issued entry briefly. For correctness, each timeline
contains dated future entries that advance without reopening the app.

## Progress without the app

The widget can move between its five supplied entries based on dates. It cannot
write back that a card was actually seen. On the next app activation,
DeckScheduler compares the time with the persistent queue, advances elapsed
entries, respects sleep windows, and replenishes the schedule.
