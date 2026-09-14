//
//  DeckHistoryView.swift
//  flashcard-widget
//
//  A single deck's own paginated History screen (ADR 0002, decision 1) --
//  there is no global History screen. Shows only reached entries
//  (`sequence <= highestReachedSequence`), sorted by `sequence`
//  descending, loaded 10 at a time.
//

import SwiftUI
import SwiftData

struct DeckHistoryView: View {
    let deck: Deck

    @State private var loadedEntries: [HistoryEntry] = []

    private var pageSize: Int { DeckScheduler.queueSize }

    var body: some View {
        List {
            ForEach(loadedEntries, id: \.persistentModelID) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    if let card = entry.card, let note = card.note {
                        if let primary = note.primaryText {
                            Text(primary).font(.headline)
                        }
                        if let secondary = note.secondaryText {
                            Text(secondary).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("This card is no longer available.")
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.projectedAt, style: .date) + Text(" ") + Text(entry.projectedAt, style: .time)
                }
                .onAppear {
                    loadMoreIfNeeded(currentEntry: entry)
                }
            }
        }
        .navigationTitle("History")
        .onAppear {
            loadFirstPageIfNeeded()
        }
    }

    private func loadFirstPageIfNeeded() {
        guard loadedEntries.isEmpty else { return }
        loadedEntries = DeckScheduler.historyPage(for: deck, offset: 0, limit: pageSize)
    }

    private func loadMoreIfNeeded(currentEntry: HistoryEntry) {
        guard currentEntry.persistentModelID == loadedEntries.last?.persistentModelID else { return }
        let nextPage = DeckScheduler.historyPage(for: deck, offset: loadedEntries.count, limit: pageSize)
        guard !nextPage.isEmpty else { return }
        loadedEntries.append(contentsOf: nextPage)
    }
}

#Preview {
    NavigationStack {
        DeckHistoryView(deck: Deck(ankiDeckID: 1, name: "Preview Deck"))
    }
    .modelContainer(for: Deck.self, inMemory: true)
}
