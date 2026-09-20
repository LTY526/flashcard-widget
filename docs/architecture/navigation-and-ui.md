# UI and navigation

[Documentation index](../README.md)

The main app uses SwiftUI with SwiftData-backed screens. Scheduling rules remain
in DeckScheduler; views coordinate user intent and present projected values.

## Screen ownership

| Screen/type | Responsibility |
|---|---|
| flashcard_widgetApp | Creates the shared container and receives widget URLs |
| ContentView | Deck list, imports, deletion, pause, mapping prompts, activation reconciliation |
| DeckDetailView | Current card, Next, configuration, pause/resume, Schedule link |
| DeckHistoryView | Upcoming and Past schedule tabs from immutable snapshots |
| FieldMappingView | Four-role field assignment and previews |
| CardWidgetView | Shared compact/expanded card presentation |

## Startup and activation gate

The app does not show database-backed content until the shared container opens.
If opening fails, the root displays Unable to Open Library with the underlying
reason. On foreground activation, ContentView reconciles elapsed schedules
under the exclusive lock before allowing normal interaction. This prevents the
deck detail from briefly showing the card that was current when the app closed.

## Deck Detail and Next

Next updates the effective pointer immediately. Rebuilding 100 future entries
can be noticeable, so repeated taps are collected for one second and produce a
single rebuild/save/reload cycle. Navigation away and other mutations flush
pending work to prevent an unsaved pointer from escaping.

Changing interval, order, sleep range, pause state, or mappings is a schedule
mutation and must use the same serialization path.

## Schedule screen

DeckHistoryView shows Upcoming and Past instead of a separate History feature.
It loads ScheduleSnapshot values through a fresh ModelContext. This sees changes
saved by background operations without replacing the SwiftUI navigation model
with objects from a different context.

## Deep links

The widget URL has this exact shape:

~~~text
flashcard-widget://deck/<persistent-deck-id>
~~~

DeckDeepLink validates the scheme, host, path shape, and identifier. The app
then selects the matching deck and navigates to its detail screen. Invalid or
deleted IDs are ignored safely.

## Presentation contract

- Widget/compact preview: primary, secondary, tertiary; left aligned.
- Expanded app card: the same roles plus quaternary.
- Long in-app tertiary/quaternary text may grow to the lines it needs.
- Widget text must fit WidgetKit's fixed family bounds and may be constrained.
