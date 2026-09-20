# Persistence and App Groups

[Documentation index](../README.md) | [Troubleshooting](../operations/troubleshooting.md)

## Why an App Group is required

The app and widget are separate processes with separate private sandboxes. A
normal app database is invisible to the widget. An App Group is an entitlement
that lets both signed executables ask iOS for one additional shared container.

This project uses:

~~~text
group.com.xyz7172.flashcard-widget
~~~

Three things must agree:

1. The identifier registered for the Apple developer team.
2. The App Groups capability in both targets and their entitlement files.
3. The provisioning profile/signature installed on the phone.

Merely placing the entitlement text in the repository does not grant access.
iOS validates the installed signature. If the signer cannot provision that
group, containerURL returns nil and SharedModelContainer reports
groupContainerUnavailable. This commonly explains why an Xcode development
install works but a third-party re-signing service does not.

## What is shared

SharedModelContainer asks FileManager for the group container, then places the
SwiftData store at Flashcards.store. SQLite may create companion WAL and SHM
files. The container also holds imported shared media and
.schedule-mutation.lock.

The identifier is stable, but the absolute on-device path is assigned by iOS
and must never be hard-coded.

## Opening the database

Both targets construct a ModelContainer with the same model schema and store
URL. The main app keeps its UI container, while operations that need a clean
view of cross-context changes may create a fresh container/context. The widget
does this for its short-lived queries and provider calls.

SwiftData uses SQLite internally today, but the SQLite layout is an
implementation detail. Application code must use SwiftData rather than querying
its generated tables.

## Cross-process locking

An App Group shares bytes, not execution. WidgetKit can launch the extension
while the app is importing or advancing a deck. ScheduleFileLock coordinates
these operations with POSIX flock on a file in the shared container:

| Lock | Users | Purpose |
|---|---|---|
| Shared | Widget deck query and timeline reads | Multiple readers may coexist |
| Exclusive | Import, Next, pause/settings, activation reconciliation | No reader observes a partially changing schedule |

Lock acquisition has a two-second timeout. Callers should surface or fall back
from a busy/unavailable state rather than deadlocking. The lock protects the
schedule operation; ModelContext save and rollback remain responsible for
database atomicity.

## Data visibility rules

- Saving one ModelContext does not guarantee another existing context refreshes
  all registered objects.
- Cross-process readers should use a fresh context and project results into
  plain values.
- Widget reload requests are hints. They tell WidgetKit that data changed but
  do not force an immediate extension launch.
- The widget never reports that an entry appeared. The app derives elapsed
  progress from stored dates when it next becomes active.

## Signing and installation

For a physical device, select a development team for both targets, enable the
same App Group in Signing & Capabilities, let Xcode generate matching profiles,
and install by running the app target. Re-signing an IPA must preserve a valid
group entitlement for both embedded executables; personal/free provisioning or
some sideloading services may not support it.

See [Build and installation](../operations/building-and-installing.md) for the
workflow and [SwiftData inspection](../operations/inspecting-swiftdata.md) before
copying or examining store files.
