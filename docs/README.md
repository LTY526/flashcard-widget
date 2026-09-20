# Flashcard Widget documentation

This project imports Anki APKG packages, stores their decks locally, schedules
cards, and displays the selected deck on an iPhone Lock Screen widget.

## System at a glance

~~~text
APKG file
   |
   v
Importer -> SwiftData models -> DeckScheduler
                               |          |
                               v          v
                         Main app UI   Widget timeline
                               \          /
                                App Group
~~~

The application and widget extension are separate executables. They communicate
through a SwiftData store inside a shared App Group container; they do not call
each other directly.

## Why the App Group is central

iOS gives every application and extension its own sandbox. The main app can
normally read only its own container, and the widget can normally read only the
widget extension container. A database saved in the app's ordinary Application
Support directory is therefore invisible to the widget.

Both targets declare the same App Group entitlement:

~~~text
group.com.xyz7172.flashcard-widget
~~~

iOS resolves that identifier to a third container that both signed targets may
open:

~~~text
Main app sandbox                  Widget extension sandbox
        |                                  |
        | same App Group entitlement       |
        +----------------+-----------------+
                         |
                         v
        Shared App Group container
        - Flashcards.store
        - SQLite WAL/SHM sidecars
        - .schedule-mutation.lock
        - shared imported media
~~~

SharedModelContainer constructs the SwiftData ModelContainer at
Flashcards.store in this group. The app imports data and mutates schedules
there. The widget opens the same store when WidgetKit requests configuration
choices, a snapshot, or a timeline.

An App Group grants filesystem access; it does **not** coordinate concurrent
database operations. The app and widget are different processes and may run at
the same time. ScheduleFileLock therefore uses a lock file in the same group:

- App imports, Next, pause, settings changes, and activation reconciliation use
  an exclusive lock.
- Widget deck queries and timeline reads use a shared lock.
- Lock attempts time out rather than waiting forever.

Entitlements are enforced by the installed signature, not merely by files in
the repository. If provisioning does not include the group, the lookup returns
nil and the app reports groupContainerUnavailable. This is why a SideStore
signature can fail while an Xcode-installed development build works.

See [Persistence and App Groups](architecture/persistence-and-app-group.md) for
container creation, signing, locking, inspection, and failure details.

## Current behavior

- Imports legacy and modern Anki collection formats from APKG archives.
- Maps note fields to primary, secondary, tertiary, and quaternary roles.
- Stores one current card plus 100 future cards per active deck.
- Sends the current card plus at most four future cards to WidgetKit.
- Supports sequential or random ordering and per-deck sleep hours.
- Reconciles elapsed scheduled cards whenever the app becomes active.
- Shows Upcoming and Past schedule partitions in Deck Detail.
- Debounces a rapid series of Next taps before rebuilding the future queue.

## Documentation map

| Document | Read this when |
|---|---|
| [Project structure](project-structure.md) | Finding the owner of a file or feature |
| [System overview](architecture/system-overview.md) | Learning the end-to-end architecture |
| [Data model](architecture/data-model.md) | Changing SwiftData models or relationships |
| [Persistence and App Groups](architecture/persistence-and-app-group.md) | Debugging shared storage, signing, or locking |
| [DeckScheduler](deck-scheduler.md) | Changing card order, progress, sleep, or Next |
| [Widget timeline](architecture/widget-timeline.md) | Changing widget selection, entries, or reloads |
| [Import pipeline](architecture/import-pipeline.md) | Changing APKG, SQLite, ZIP, Zstd, media, or re-import |
| [UI and navigation](architecture/navigation-and-ui.md) | Changing screens, deep links, or activation behavior |
| [Testing strategy](architecture/testing-strategy.md) | Adding tests or understanding fixtures |
| [Build and installation](operations/building-and-installing.md) | Installing from Xcode or diagnosing signing |
| [SwiftData inspection](operations/inspecting-swiftdata.md) | Examining a simulator/device store safely |
| [Troubleshooting](operations/troubleshooting.md) | Resolving common app/widget failures |

Architecture decisions are in [decisions](decisions/), implementation contracts
are in [specs](specs/), and device checklists are in [testing](testing/).

## Suggested reading paths

New contributor:

1. This page
2. [Project structure](project-structure.md)
3. [System overview](architecture/system-overview.md)
4. The deep dive for the feature being changed

Scheduling or widget bug:

1. [DeckScheduler](deck-scheduler.md)
2. [Widget timeline](architecture/widget-timeline.md)
3. [Persistence and App Groups](architecture/persistence-and-app-group.md)

Import bug:

1. [Import pipeline](architecture/import-pipeline.md)
2. [Data model](architecture/data-model.md)
3. [Testing strategy](architecture/testing-strategy.md)
