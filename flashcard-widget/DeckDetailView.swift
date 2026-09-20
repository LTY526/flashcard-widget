//
//  DeckDetailView.swift
//  flashcard-widget
//
//  Per-deck screen: current card (via that deck's own scheduled queue),
//  Next, pause/resume, its one `DisplayConfig` editable in place, and
//  a link to this deck's own paginated History screen (ADR 0002,
//  decision 1). The active card uses the same reusable `CardWidgetView` as
//  field-mapping previews.
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    let scheduleRevision: Int
    @Environment(\.modelContext) private var modelContext

    init(deck: Deck, scheduleRevision: Int = 0) {
        self.deck = deck
        self.scheduleRevision = scheduleRevision
    }

    var body: some View {
        let _ = scheduleRevision
        Form {
            Section("Current Card") {
                currentCardContent
                Button {
                    do {
                        try ScheduleFileLock.shared().withExclusiveLock {
                            try DeckScheduler.next(deck, in: modelContext, now: Date())
                            try modelContext.save()
                        }
                        Task {
                            await WidgetTimelineReloader.shared.scheduleReload()
                        }
                    } catch {
                        // Keep the current card when advancing or saving fails.
                    }
                } label: {
                    Label("Next", systemImage: "arrow.right")
                }
                .disabled(deck.isPaused || deck.activeCards.isEmpty)
            }

            Section {
                Toggle("Paused", isOn: Binding(
                    get: { deck.isPaused },
                    set: { newValue in
                        guard newValue != deck.isPaused else { return }
                        do {
                            try ScheduleFileLock.shared().withExclusiveLock {
                                try DeckScheduler.setPaused(
                                    newValue,
                                    deck: deck,
                                    in: modelContext,
                                    now: Date()
                                )
                                try modelContext.save()
                            }
                            Task {
                                await WidgetTimelineReloader.shared.scheduleReload()
                            }
                        } catch {
                            // Keep the last saved pause state when updating fails.
                            modelContext.rollback()
                        }
                    }
                ))
            } footer: {
                Text("Pausing clears upcoming cards and updates the widget. Resuming starts a new schedule.")
            }

            if let config = deck.displayConfig {
                DisplayConfigSection(deck: deck, config: config)
            }

            Section {
                NavigationLink {
                    DeckHistoryView(deck: deck, scheduleRevision: scheduleRevision)
                } label: {
                    Label("Schedule", systemImage: "calendar")
                }
            }
        }
        .navigationTitle(deck.name)
        .onAppear {
            if deck.displayConfig == nil {
                deck.displayConfig = DisplayConfig()
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
                Text("This card is no longer available.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No card yet -- tap Next to begin.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Editable-in-place `DisplayConfig` fields. Exactly one config always
/// exists per deck -- there's no "add another" or "switch which one is in
/// use" UI.
private struct DisplayConfigSection: View {
    let deck: Deck
    @Bindable var config: DisplayConfig
    @Environment(\.modelContext) private var modelContext
    @State private var intervalText: String = ""

    var body: some View {
        Section {
            Picker("Order", selection: Binding(
                get: { config.order },
                set: { newOrder in
                    guard newOrder != config.order else { return }
                    applyScheduleEdit {
                        config.order = newOrder
                    }
                }
            )) {
                Text("Sequential").tag(DisplayOrder.sequential)
                Text("Random").tag(DisplayOrder.random)
            }

            Stepper(value: Binding(
                get: { config.intervalMinutes },
                set: { candidate in
                    guard candidate != config.intervalMinutes else { return }
                    applyScheduleEdit { config.updateIntervalMinutes(candidate) }
                }
            ), in: DisplayConfig.minimumIntervalMinutes...1440, step: 5) {
                Text("Interval: \(config.intervalMinutes) min")
            }

            Stepper("New cards a day: \(config.newCardsADay)", value: $config.newCardsADay, in: 0...200)

            Toggle("Review previous-day cards", isOn: $config.reviewPreviousDayCards)

            Toggle("Sleep Schedule", isOn: Binding(
                get: { config.sleepEnabled },
                set: { enabled in updateSleep(enabled: enabled) }
            ))
            DatePicker("Sleep starts", selection: minuteBinding(\.sleepStartMinute), displayedComponents: .hourAndMinute)
            DatePicker("Wake time", selection: minuteBinding(\.sleepEndMinute), displayedComponents: .hourAndMinute)
        } header: {
            Text("Display Config")
        } footer: {
            Text("Automatic progress stops during the sleep range. Start and wake times remain editable while disabled.")
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

    private func applyScheduleEdit(_ edit: () throws -> Void) {
        do {
            try ScheduleFileLock.shared().withExclusiveLock {
                try edit()
                try DeckScheduler.rebuildFuture(for: deck, in: modelContext, now: Date())
                try modelContext.save()
            }
            Task { await WidgetTimelineReloader.shared.scheduleReload() }
        } catch {
            modelContext.rollback()
        }
    }
}

#Preview {
    NavigationStack {
        DeckDetailView(deck: Deck(ankiDeckID: 1, name: "Preview Deck"))
    }
    .modelContainer(for: Deck.self, inMemory: true)
}
