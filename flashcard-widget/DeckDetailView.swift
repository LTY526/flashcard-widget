//
//  DeckDetailView.swift
//  flashcard-widget
//
//  Per-deck screen: current card (via that deck's own scheduled queue),
//  Next/Back, pause/resume, its one `DisplayConfig` editable in place, and
//  a link to this deck's own paginated History screen (ADR 0002,
//  decision 1). The active card uses the same reusable `CardWidgetView` as
//  field-mapping previews.
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Current Card") {
                currentCardContent
                HStack {
                    Button {
                        DeckScheduler.back(deck)
                    } label: {
                        Label("Back", systemImage: "arrow.left")
                    }
                    .disabled(!DeckScheduler.canGoBack(deck))

                    Spacer()

                    Button {
                        DeckScheduler.next(deck, in: modelContext)
                    } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .disabled(deck.isPaused || deck.activeCards.isEmpty)
                }
            }

            Section {
                Toggle("Paused", isOn: Binding(
                    get: { deck.isPaused },
                    set: { newValue in
                        deck.isPaused = newValue
                        if !newValue {
                            DeckScheduler.readSchedule(for: deck, in: modelContext)
                        }
                    }
                ))
            } footer: {
                Text("While paused, this deck's Next is a no-op and its queue isn't regenerated.")
            }

            if let config = deck.displayConfig {
                DisplayConfigSection(deck: deck, config: config)
            }

            Section {
                NavigationLink {
                    DeckHistoryView(deck: deck)
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle(deck.name)
        .onAppear {
            if deck.displayConfig == nil {
                deck.displayConfig = DisplayConfig()
            }
            DeckScheduler.readSchedule(for: deck, in: modelContext)
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
                    config.order = newOrder
                    DeckScheduler.handleOrderChange(for: deck, in: modelContext)
                }
            )) {
                Text("Sequential").tag(DisplayOrder.sequential)
                Text("Random").tag(DisplayOrder.random)
            }

            Stepper(value: Binding(
                get: { config.intervalMinutes },
                set: { config.updateIntervalMinutes($0) }
            ), in: DisplayConfig.minimumIntervalMinutes...1440, step: 5) {
                Text("Interval: \(config.intervalMinutes) min")
            }

            Stepper("New cards a day: \(config.newCardsADay)", value: $config.newCardsADay, in: 0...200)

            Toggle("Review previous-day cards", isOn: $config.reviewPreviousDayCards)
        } header: {
            Text("Display Config")
        } footer: {
            Text("Interval is advisory spacing between cards (minimum \(DisplayConfig.minimumIntervalMinutes) minutes), not a guaranteed exact countdown. \"New cards a day\" and \"Review previous-day cards\" are stored but not yet enforced.")
        }
    }
}

#Preview {
    NavigationStack {
        DeckDetailView(deck: Deck(ankiDeckID: 1, name: "Preview Deck"))
    }
    .modelContainer(for: Deck.self, inMemory: true)
}
