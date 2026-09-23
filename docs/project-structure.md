# Project structure

This is a responsibility map of the tracked repository. Generated Xcode
products and local Derived Data are not part of the repository.

## Top level

| Path | Role |
|---|---|
| flashcard-widget.xcodeproj/ | Xcode project, target membership, build phases, capabilities, and local scheme metadata |
| flashcard-widget/ | Main iOS application target and source shared with the widget target |
| FlashcardWidget/ | Widget extension target |
| flashcard-widget-tests/ | Swift Testing unit and acceptance tests plus APKG fixtures |
| docs/ | Architecture decisions, specifications, guides, and checklists |
| scripts/build-unsigned-ipa.sh | Produces an unsigned IPA archive for external signing workflows |
| .claude/skills/ | Repository-local planning and execution workflow instructions |
| .gitignore | Files Git must not track |

The project.pbxproj file is Xcode-managed. Do not hand-edit it while Xcode is
open. The xcuserdata subtree is machine/user-specific and is not architecture.

| Xcode project file | Role |
|---|---|
| project.pbxproj | Canonical target, source membership, build setting, capability, and build-phase definitions |
| project.xcworkspace/contents.xcworkspacedata | Workspace wrapper that tells Xcode to open the project itself |
| xcuserdata/.../xcschememanagement.plist | Per-user scheme visibility/order; local IDE state rather than product logic |

## Main application

### Entry and screens

| File | Role and usage |
|---|---|
| flashcard_widgetApp.swift | App entry point; creates the shared ModelContainer, displays store-opening errors, and routes widget deep links |
| ContentView.swift | Deck list, APKG import/removal, pause actions, foreground reconciliation gate, mapping prompts, and deep-link navigation |
| DeckDetailView.swift | Current, Schedule, and Config modes; current card, Next, pause/resume, and effective schedule settings |
| DeckHistoryView.swift | Read-only Upcoming/Past Schedule UI; loads value snapshots through a fresh context so background commits appear without resetting navigation |
| FieldMappingView.swift | Assigns Anki fields to display roles and provides live widget/in-app previews |
| CardWidgetView.swift | Reusable card presentation for mapping previews and Deck Detail; supports compact three-row and expanded four-role forms |
| WidgetTimelineReloader.swift | Actor that coalesces repeated WidgetKit reload requests |
| Navigation/DeckDeepLink.swift | Strict parser for flashcard-widget://deck/<id> URLs |
| Navigation/DeckDetailRoute.swift | Detail mode, Schedule subsection, and deferred deep-link route state |
| Scheduling/PendingNextCoordinator.swift | Root-owned debounced Next anchors, flush, retry, and mutation gate |

### SwiftData models

| File | Role and usage |
|---|---|
| Models/Deck.swift | Root per-deck object, active cards, schedule pointer/watermark, pause state, config, and history relationships |
| Models/Card.swift | Anki card identity and relationships to its deck and note; supports soft deletion |
| Models/Note.swift | Anki note, raw fields, note type, cards/media, and computed text for four display roles |
| Models/NoteType.swift | Globally shared Anki model identity and field-mapping completeness |
| Models/NoteTypeField.swift | Field name, ordinal, owning note type, and assigned FieldRole |
| Models/FieldRole.swift | Stable primary/secondary/tertiary/quaternary role values |
| Models/DisplayConfig.swift | Per-deck order, interval, daily options, sleep range, and schedule timezone metadata |
| Models/DisplayOrder.swift | Sequential/random persisted ordering enum |
| Models/HistoryEntry.swift | A sequence number, projected date, card relationship, and owning deck; represents current, past, or future based on the watermark |
| Models/MediaItem.swift | Imported media filename/path and note relationship |

### Scheduling and persistence

| File | Role and usage |
|---|---|
| Scheduling/DeckScheduler.swift | Validates, seeds, advances, reconciles, pauses, rebuilds, and tops up the 100-entry future queue |
| Scheduling/SleepSchedule.swift | Pure calendar/time-zone-aware sleep membership and awake-time addition |
| Scheduling/ScheduleSelector.swift | Read-only effective-current selection and plain Sendable timeline values used by app/widget tests and provider code |
| Persistence/SharedModelContainer.swift | Defines the full SwiftData schema and opens Flashcards.store in the App Group |
| Persistence/ScheduleFileLock.swift | Cross-process shared/exclusive flock coordination for the app and widget |

### APKG import

| File | Role and usage |
|---|---|
| ApkgImport/ApkgImporter.swift | Orchestrates package load, parse, upsert, soft deletion, mapping, media, schedule repair, and the final save |
| ApkgImport/ApkgImportError.swift | Stable user-facing import failure categories |
| ApkgImport/ApkgPackageLoader.swift | Opens the ZIP, selects the collection member, handles Zstd, and exposes media members |
| ApkgImport/CollectionSchemaDetector.swift | Detects supported legacy or modern Anki database layouts |
| ApkgImport/LegacyCollectionParser.swift | Parses collection.anki2 JSON-backed metadata and rows |
| ApkgImport/ModernCollectionParser.swift | Parses modern normalized collection tables |
| ApkgImport/ParsedCollection.swift | Parser-neutral value objects and Anki field-value splitting/cleanup |
| ApkgImport/FieldMappingService.swift | Applies automatic mappings based on field names |
| ApkgImport/MediaImporter.swift | Copies referenced package media and creates MediaItem records |
| ApkgImport/DeckRemover.swift | Deletes a deck and safely removes notes/media no longer shared by another active deck |
| ApkgImport/SQLite/SQLiteConnection.swift | Minimal SQLite wrapper used only to read Anki collection databases |
| ApkgImport/Zip/ZipArchiveReader.swift | In-process ZIP central-directory reader and extractor |
| ApkgImport/Zstd/ZstdDecompressor.swift | Swift wrapper around bundled native Zstandard decompression |

### Resources and configuration

| Path | Role |
|---|---|
| Assets.xcassets/ | Main app icon/accent catalogs |
| Info.plist | Main target configuration and imported document declarations |
| flashcard-widget.entitlements | Main target App Group entitlement |
| BridgingHeader.h | Exposes the bundled Zstandard C API to Swift |
| ThirdParty/zstd/ | Vendored Zstandard decompression sources and upstream license; application code should use ZstdDecompressor rather than these files directly |

Files below ThirdParty/zstd/lib/common and lib/decompress are upstream C
implementation units and headers. They provide allocation, bitstream, entropy,
Huffman, dictionary, frame, block, error, hashing, portability, and public API
support. They are not project business logic and should normally be updated as
one vendored library rather than edited individually.

## Widget extension

| File | Role and usage |
|---|---|
| FlashcardWidget.swift | AppIntent timeline provider, shared-store read, widget states, three-row view, deep-link URL, configuration, and previews |
| AppIntent.swift | Deck AppEntity, shared-store EntityQuery, and configurable widget intent |
| FlashcardWidgetBundle.swift | Widget extension entry point |
| Info.plist | Extension metadata |
| FlashcardWidgetExtension.entitlements | Widget target App Group entitlement; must match the app target |
| Assets.xcassets/ | Widget extension assets and generated catalog metadata |

## Tests and fixtures

| File/path | Role |
|---|---|
| ApkgImportTests.swift | Package variants, re-import, mapping, errors, media, atomic failure, and widget reload orchestration |
| DeckSchedulerTests.swift | Queue invariants, ordering, Next, pause, reset, history pagination, and config behavior |
| SleepAwareScheduleAcceptanceTests.swift | Sleep/DST/timezone, activation atomicity, provider parity, Schedule snapshots, and four-role acceptance coverage |
| ConfigurableWidgetAcceptanceTests.swift | Queue seed, provider selection, malformed schedules, resume, immediate Next/deferred rebuild, and deep-link grammar |
| CardWidgetViewTests.swift | Role aggregation and plain card-content behavior |
| DeckRemoverTests.swift | Cascade/shared-note/media deletion behavior |
| Fixtures.swift | Test-only ModelContainer and graph construction helpers |
| flashcard_widgetTests.swift | Template/smoke test target entry |
| Fixtures/*.apkg | Deliberately valid, missing, damaged, removed-card, fallback, single-field, and unsupported Anki packages |

## Documentation

| Path | Meaning |
|---|---|
| decisions/ | ADRs: why architectural choices were made and what they supersede |
| specs/ | Verifiable behavior contracts and scope boundaries |
| architecture/ | Maintainer-oriented explanations of how current code works |
| operations/ | Build, installation, inspection, and troubleshooting procedures |
| testing/ | Manual device verification checklists |
| README.md | Documentation entry point and App Group introduction |
| project-structure.md | This repository responsibility map |
| deck-scheduler.md | Detailed persistent queue and timing algorithm |
| decisions/0001-anki-lockscreen-widget-architecture.md | Original app/import/widget architecture decision |
| decisions/0002-active-card-history-and-display-config.md | Active card, history, and deck configuration decision |
| decisions/0003-configurable-lock-screen-widget.md | Deck-selectable widget and shared schedule behavior decision |
| decisions/0004-sleep-aware-schedule-and-four-field-display.md | Sleep scheduling, queue, schedule UI, and four-role decision |
| specs/apkg-import.md | APKG compatibility and import acceptance contract |
| specs/active-card-deck-management.md | Deck progress/configuration behavior contract |
| specs/configurable-lock-screen-widget.md | Widget selection, timeline, and deep-link contract |
| specs/reusable-card-view.md | Shared card presentation contract |
| specs/sleep-aware-schedule-and-four-field-display.md | Current sleep/schedule/display behavior contract |
| testing/sleep-aware-schedule-device-checklist.md | Manual device acceptance checklist for scheduling and widget behavior |

Every file in architecture/ and operations/ is a current-behavior guide linked
from the [documentation index](README.md). Asset catalog Contents.json files are
Xcode metadata for their containing color/icon set. APKG fixtures are described
as a set above because they are binary test inputs, and the vendored Zstandard
files are described as one upstream library rather than as application-owned
modules.

ADRs and specs are historical contracts. Architecture guides describe the
current implementation and should be updated with relevant code changes.
