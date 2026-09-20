# Testing strategy

[Documentation index](../README.md)

The test target uses Swift Testing for deterministic model, scheduler, import,
and acceptance coverage. Device behavior that belongs to WidgetKit or signing
still requires the manual checklists in docs/testing.

## Test layers

| File | Main coverage |
|---|---|
| DeckSchedulerTests.swift | Queue invariants, order, Next, pause, config, pagination |
| SleepAwareScheduleAcceptanceTests.swift | Sleep boundaries, DST/timezone, foreground reconciliation, snapshots |
| ConfigurableWidgetAcceptanceTests.swift | Widget selection/projection, malformed schedules, deep links, deferred rebuild |
| ApkgImportTests.swift | Formats, re-import, media, failures, mappings, reload orchestration |
| DeckRemoverTests.swift | Cascades and shared note/media retention |
| CardWidgetViewTests.swift | Display-role aggregation and plain content behavior |

Fixtures.swift creates isolated in-memory ModelContainers and graph builders.
APKG fixtures intentionally cover valid, corrupt, absent, fallback, and
unsupported package conditions.

## Determinism

Scheduler APIs accept or derive explicit reference dates, calendars, and time
zones so tests do not depend on the wall clock. Random ordering is tested by
invariants rather than assuming a specific unstable shuffle unless a seeded
source is provided.

## What unit tests cannot prove

- The installed provisioning profile grants the App Group.
- Widget configuration works on the real Lock Screen.
- WidgetKit honors a reload request immediately.
- A deep link launches and navigates correctly from a real widget.
- Typography fits every device and accessibility setting.

Run the relevant device checklist after changes to entitlements, WidgetKit,
deep links, or presentation. For source changes, refresh per-file diagnostics,
run the focused test group, then build the complete Xcode project.
