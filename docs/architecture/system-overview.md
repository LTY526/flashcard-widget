# System overview

[Documentation index](../README.md) | [Project structure](../project-structure.md)

The repository produces two installed executables: the main SwiftUI app and a
WidgetKit extension. Both read one SwiftData database in an App Group, but only
the app performs schedule mutations.

~~~text
                    Shared App Group
                 +--------------------+
APKG -> main app | SwiftData database | <- widget configuration
        import   | media files        | -> widget timeline
        schedule | process lock       |
                 +--------------------+
~~~

## Responsibility boundaries

| Component | Owns | Does not own |
|---|---|---|
| Main app | Import, mapping, schedule mutation, settings, reconciliation | Widget rendering cadence |
| DeckScheduler | Persistent queue and progress rules | UI and WidgetKit reload policy |
| Widget extension | Deck selection, snapshots, timeline entries, rendering | Marking cards viewed or changing schedules |
| SharedModelContainer | Schema and shared store location | Cross-process serialization |
| ScheduleFileLock | Cross-process read/write exclusion | SwiftData transactions |

## Important flows

### Import

ContentView starts an ImportOperation. The importer opens the APKG, parses its
Anki SQLite database, imports media, upserts SwiftData objects, soft-deletes
missing cards, repairs the schedule, and saves once. Incomplete mappings are
presented before the deck becomes useful to the widget.

### App activation

When the app becomes active, ContentView acquires the exclusive schedule lock
and opens a fresh shared ModelContext. DeckScheduler reconciles every active
deck against the current time. The visible context is then refreshed and
WidgetKit is asked to reload only if shared state changed.

### Widget request

WidgetKit launches the extension on its own schedule. The provider acquires a
shared lock, opens the shared store, resolves the selected deck, and converts
the effective current card plus four future items into timeline entries. It
returns explicit empty, paused, unavailable, or ready states instead of
mutating the schedule.

### Next

Next exists only in Deck Detail. It advances the persistent pointer
immediately so the UI is correct, while rebuilding the 100-card future queue
after a one-second debounce. Leaving the screen flushes pending work.

## Consistency model

SwiftData contexts do not automatically make every already-loaded object graph
fresh after another process or context saves. Code that must see external
changes opens a fresh context and passes plain value snapshots back to the UI.
The lock prevents overlapping schedule reads and writes; SwiftData save/rollback
still provides the database transaction boundary.

For the details, see [Persistence and App Groups](persistence-and-app-group.md),
[DeckScheduler](../deck-scheduler.md), and [Widget timeline](widget-timeline.md).
