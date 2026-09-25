# UI and navigation

[Documentation index](../README.md)

The main app uses SwiftUI with SwiftData-backed screens. Scheduling rules remain
in DeckScheduler; views coordinate user intent and present projected values.

## Screen ownership

| Screen/type | Responsibility |
|---|---|
| flashcard_widgetApp | Creates the shared container and receives widget URLs |
| ContentView | Deck list, imports, deletion, pause, mapping prompts, activation reconciliation, onboarding entry points and sheet scheduling |
| DeckDetailView | Current card, Next, configuration, pause/resume, Schedule link |
| OnboardingView | Five-step instructional guide with Back, Next/Finish, Dismiss, and manual Restart |
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

Deck Detail has Current, Schedule, and Config modes. Current contains the card,
Next, and pause control. Schedule keeps its Upcoming/Past selection while its
value snapshot refreshes on entry. Config contains order, interval, sleep, and
field mapping.

Next updates the effective pointer immediately. Rebuilding 100 future entries
can be noticeable, so repeated taps are collected for one second and produce a
single rebuild/save/reload cycle. The root coordinator keeps pending anchors
across navigation. A failed flush leaves the anchor available for Retry and
blocks dependent schedule changes until it succeeds.

Changing interval, order, sleep range, pause state, or mappings is a schedule
mutation and must use the same serialization path.

## Schedule mode

DeckHistoryView shows Upcoming and Past.
It loads ScheduleSnapshot values through a fresh ModelContext. This sees changes
saved by background operations without replacing the SwiftUI navigation model
with objects from a different context.

## Deep links

The widget URL has this exact shape:

~~~text
flashcard-widget://deck/<anki-deck-id>
~~~

DeckDeepLink validates the scheme, host, path shape, and identifier. The app
then selects the matching deck and navigates to Current. On cold launch it waits
for activation to complete before resolving the saved deck. Invalid or deleted
IDs return to the deck list.

## Getting Started

After successful library activation, ContentView presents the five-step guide
once for each new onboarding version. It waits for the file picker, mapping
sheet, alerts, removal dialog, and other active work to close. An outstanding
automatic introduction stays pending if the user starts a manual replay first;
it appears after that sheet closes. Both the permanent Getting Started toolbar
action and the temporary Test Onboarding button on the root deck page open a
manual replay, including when the library has no decks.

The guide only explains where to use existing app and system controls. It does
not import, configure, or schedule anything. The first three steps show
advisory completion based on a live SwiftData query converted to plain observed
values. Dismiss and Finish acknowledge the current version only for automatic
presentation. A sheet swipe follows the same dismissal path. Manual Restart
returns to step one without changing the saved acknowledgement.

## Presentation contract

- Widget/compact preview: primary, secondary, tertiary; left aligned.
- Expanded app card: the same roles plus quaternary.
- Long in-app tertiary/quaternary text may grow to the lines it needs.
- Widget text must fit WidgetKit's fixed family bounds and may be constrained.
