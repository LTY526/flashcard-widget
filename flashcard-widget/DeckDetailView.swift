//
//  DeckDetailView.swift
//  flashcard-widget
//
//  Per-deck Current, Schedule, and Config modes. Current uses the same
//  reusable CardWidgetView as field-mapping previews. The root coordinator
//  owns pending Next rebuilds across mode changes and navigation.
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Binding var route: DeckDetailRoute
    let coordinator: PendingNextCoordinator
    var editMapping: (Deck) -> Void = { _ in }
    let scheduleRevision: Int
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scheduleSnapshot: ScheduleSnapshot?
    @State private var failedAction: (() -> Void)?
    @State private var showsActionError = false

    init(
        deck: Deck,
        route: Binding<DeckDetailRoute>,
        coordinator: PendingNextCoordinator,
        scheduleRevision: Int = 0,
        editMapping: @escaping (Deck) -> Void = { _ in }
    ) {
        self.deck = deck
        self._route = route
        self.coordinator = coordinator
        self.scheduleRevision = scheduleRevision
        self.editMapping = editMapping
    }

    var body: some View {
        let controls = DeckDetailControl.visible(in: route.mode)
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                modePicker.pickerStyle(.menu)
            } else {
                modePicker.pickerStyle(.segmented)
            }

            if controls.contains(.schedule) {
                DeckHistoryView(
                    deck: deck,
                    tab: $route.scheduleTab,
                    initialSnapshot: scheduleSnapshot,
                    scheduleRevision: scheduleRevision
                )
            } else if controls.contains(.currentCard) {
                currentView(controls)
            } else {
                configView(controls)
            }
        }
        .navigationTitle(deck.name)
        .onDisappear {
            do { try coordinator.flush(deckIDs: [deck.ankiDeckID]) }
            catch { /* root-owned coordinator displays Retry after a system pop */ }
        }
        .alert("Unable to Update Schedule", isPresented: $showsActionError) {
            Button("Retry") { failedAction?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The schedule could not be saved. Please try again.")
        }
    }

    private var modePicker: some View {
        Picker("Deck detail mode", selection: Binding(
                get: { route.mode },
                set: { selectMode($0) }
            )) {
                ForEach(DeckDetailRoute.Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .accessibilityLabel("Deck detail mode")
            .accessibilityValue(route.mode.rawValue)
            .padding()
    }

    private func selectMode(_ mode: DeckDetailRoute.Mode) {
        guard mode != route.mode else { return }
        do {
            if mode == .schedule {
                scheduleSnapshot = try DeckScheduleEntry.load(
                    deckID: deck.persistentModelID,
                    ankiDeckID: deck.ankiDeckID,
                    from: modelContext.container,
                    coordinator: coordinator
                )
            } else if route.mode == .current {
                try coordinator.flush(deckIDs: [deck.ankiDeckID])
            }
        } catch {
            return
        }
        route.select(mode)
    }

    private func currentView(_ controls: [DeckDetailControl]) -> some View {
        Form {
            ForEach(controls) { control in
                switch control {
                case .currentCard:
                    Section("Current Card") { currentCardContent }
                case .next:
                    Section {
                        Button {
                            advance(at: Date())
                        } label: {
                            Label("Next", systemImage: "arrow.right")
                        }
                        .disabled(deck.isPaused || deck.activeCards.isEmpty)
                    }
                case .pause:
                    Section {
                        Toggle("Paused", isOn: Binding(
                            get: { deck.isPaused },
                            set: { newValue in
                                guard newValue != deck.isPaused else { return }
                                updatePause(newValue)
                            }
                        ))
                    } footer: {
                        Text("Pausing clears upcoming cards and updates the widget. Resuming starts a new schedule.")
                    }
                default:
                    EmptyView()
                }
            }
        }
    }

    private func advance(at now: Date) {
        do {
            try coordinator.performNextMutation(deckID: deck.ankiDeckID) {
                try ScheduleFileLock.shared().withExclusiveLock {
                    try DeckScheduler.advanceImmediately(deck, in: modelContext, now: now)
                    try modelContext.save()
                }
            }
            coordinator.schedule(deckID: deck.ankiDeckID, after: now)
            failedAction = nil
            showsActionError = false
        } catch {
            modelContext.rollback()
            if coordinator.errorMessage == nil {
                failedAction = { advance(at: now) }
                showsActionError = true
            }
        }
    }

    private func updatePause(_ newValue: Bool) {
        do {
            try coordinator.performMutation(affectedDeckIDs: [deck.ankiDeckID]) {
                try ScheduleFileLock.shared().withExclusiveLock {
                    try DeckScheduler.setPaused(newValue, deck: deck, in: modelContext, now: Date())
                    try modelContext.save()
                }
            }
            failedAction = nil
            showsActionError = false
            Task { await WidgetTimelineReloader.shared.scheduleReload() }
        } catch {
            modelContext.rollback()
            if coordinator.errorMessage == nil {
                failedAction = { updatePause(newValue) }
                showsActionError = true
            }
        }
    }

    private func configView(_ controls: [DeckDetailControl]) -> some View {
        Form {
            if let config = deck.displayConfig {
                DisplayConfigSection(
                    deck: deck,
                    config: config,
                    coordinator: coordinator,
                    controls: controls.filter(\.isConfigurationSetting)
                )
            }
            ForEach(controls) { control in
                if control == .fieldMapping {
                    Section {
                        Button {
                            editMapping(deck)
                        } label: {
                            Label("Field Mapping", systemImage: "slider.horizontal.3")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentCardContent: some View {
        if let entry = deck.activeHistoryEntry {
            if let card = entry.card, let note = card.note {
                CardWidgetView(
                    primary: note.primaryText,
                    secondary: note.secondaryText,
                    tertiary: note.tertiaryText,
                    quaternary: note.quaternaryText,
                    presentation: .inApp
                )
            } else {
                Text("This card is no longer available.").foregroundStyle(.secondary)
            }
        } else {
            Text("No card yet -- tap Next to begin.").foregroundStyle(.secondary)
        }
    }
}

/// Editable-in-place `DisplayConfig` fields. Exactly one config always
/// exists per deck -- there's no "add another" or "switch which one is in
/// use" UI.
private struct DisplayConfigSection: View {
    let deck: Deck
    @Bindable var config: DisplayConfig
    let coordinator: PendingNextCoordinator
    let controls: [DeckDetailControl]
    @Environment(\.modelContext) private var modelContext
    @State private var failedEdit: (() throws -> Void)?
    @State private var showsSaveError = false

    var body: some View {
        Section {
            ForEach(controls) { control in
                switch control {
                case .order:
                    Picker("Order", selection: Binding(
                        get: { config.order },
                        set: { newOrder in
                            guard newOrder != config.order else { return }
                            applyScheduleEdit { config.order = newOrder }
                        }
                    )) {
                        Text("Sequential").tag(DisplayOrder.sequential)
                        Text("Random").tag(DisplayOrder.random)
                    }
                case .interval:
                    Stepper(value: Binding(
                        get: { config.intervalMinutes },
                        set: { candidate in
                            guard candidate != config.intervalMinutes else { return }
                            applyScheduleEdit { config.updateIntervalMinutes(candidate) }
                        }
                    ), in: DisplayConfig.minimumIntervalMinutes...1440, step: 5) {
                        Text("Interval: \(config.intervalMinutes) min")
                    }
                case .sleepEnabled:
                    Toggle("Sleep Schedule", isOn: Binding(
                        get: { config.sleepEnabled },
                        set: { enabled in updateSleep(enabled: enabled) }
                    ))
                case .sleepStart:
                    DatePicker("Sleep starts", selection: minuteBinding(\.sleepStartMinute), displayedComponents: .hourAndMinute)
                case .wakeTime:
                    DatePicker("Wake time", selection: minuteBinding(\.sleepEndMinute), displayedComponents: .hourAndMinute)
                default:
                    EmptyView()
                }
            }
        } header: {
            Text("Display Config")
        } footer: {
            Text("Automatic progress stops during the sleep range. Start and wake times remain editable while disabled.")
        }
        .alert("Unable to Save Configuration", isPresented: $showsSaveError) {
            Button("Retry") {
                if let failedEdit { applyScheduleEdit(failedEdit) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The schedule setting could not be saved. Please try again.")
        }
    }

    private func minuteBinding(_ keyPath: ReferenceWritableKeyPath<DisplayConfig, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: config[keyPath: keyPath] / 60, minute: config[keyPath: keyPath] % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            guard minute != config[keyPath: keyPath] else { return }
            applyScheduleEdit {
                try config.updateSleep(
                    enabled: config.sleepEnabled,
                    startMinute: keyPath == \.sleepStartMinute ? minute : config.sleepStartMinute,
                    endMinute: keyPath == \.sleepEndMinute ? minute : config.sleepEndMinute
                )
            }
        }
    }

    private func updateSleep(enabled: Bool) {
        applyScheduleEdit {
            try config.updateSleep(enabled: enabled, startMinute: config.sleepStartMinute, endMinute: config.sleepEndMinute)
        }
    }

    private func applyScheduleEdit(_ edit: @escaping () throws -> Void) {
        do {
            try coordinator.performMutation(affectedDeckIDs: [deck.ankiDeckID]) {
                try ScheduleFileLock.shared().withExclusiveLock {
                    try edit()
                    try DeckScheduler.rebuildFuture(for: deck, in: modelContext, now: Date())
                    try modelContext.save()
                }
            }
            failedEdit = nil
            showsSaveError = false
            Task { await WidgetTimelineReloader.shared.scheduleReload() }
        } catch {
            modelContext.rollback()
            failedEdit = edit
            showsSaveError = true
        }
    }
}

#Preview {
    NavigationStack {
        DeckDetailView(deck: Deck(ankiDeckID: 1, name: "Preview Deck"), route: .constant(DeckDetailRoute()), coordinator: PendingNextCoordinator())
    }
    .modelContainer(for: Deck.self, inMemory: true)
}
