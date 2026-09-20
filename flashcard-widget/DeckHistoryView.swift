import SwiftUI
import SwiftData

/// Model-backed partition used by scheduler unit tests and non-UI callers.
/// The visible screen uses `ScheduleSnapshot` below so external saves cannot
/// leave it reading stale registered model instances.
struct SchedulePartition {
    let isValid: Bool
    let upcoming: [HistoryEntry]
    let past: [HistoryEntry]

    init(deck: Deck) {
        let valid: Bool
        switch (deck.activeHistoryEntry, deck.highestReachedSequence) {
        case (nil, nil):
            valid = true
        case let (entry?, watermark?):
            valid = entry.sequence == watermark &&
                entry.deck?.persistentModelID == deck.persistentModelID &&
                deck.historyEntries.contains { $0.persistentModelID == entry.persistentModelID } &&
                DeckScheduler.isRenderable(entry)
        default:
            valid = false
        }
        isValid = valid
        guard valid else {
            upcoming = []
            past = []
            return
        }
        guard let watermark = deck.highestReachedSequence else {
            upcoming = deck.historyEntries.sorted { $0.sequence < $1.sequence }
            past = []
            return
        }
        upcoming = deck.historyEntries.filter { $0.sequence >= watermark }.sorted { $0.sequence < $1.sequence }
        past = deck.historyEntries.filter { $0.sequence < watermark }.sorted { $0.sequence > $1.sequence }
    }

    func pastPage(limit: Int) -> [HistoryEntry] {
        Array(past.prefix(max(0, limit)))
    }
}

/// A value snapshot of the persisted schedule. Loading through a disposable
/// context avoids reusing models registered before a background reconciliation
/// committed. Value rows also let an already-visible screen refresh without
/// replacing its navigation or tab state.
struct ScheduleSnapshot {
    struct Row: Identifiable, Equatable {
        let sequence: Int
        let projectedAt: Date
        let title: String
        let isCurrent: Bool

        var id: Int { sequence }
    }

    let isValid: Bool
    let upcoming: [Row]
    let past: [Row]

    init(deck: Deck) {
        let valid: Bool
        switch (deck.activeHistoryEntry, deck.highestReachedSequence) {
        case (nil, nil):
            valid = true
        case let (entry?, watermark?):
            valid = entry.sequence == watermark &&
                entry.deck?.persistentModelID == deck.persistentModelID &&
                deck.historyEntries.contains { $0.persistentModelID == entry.persistentModelID } &&
                DeckScheduler.isRenderable(entry)
        default:
            valid = false
        }

        isValid = valid
        guard valid else {
            upcoming = []
            past = []
            return
        }

        let watermark = deck.highestReachedSequence
        let currentID = deck.activeHistoryEntry?.persistentModelID
        let rows = deck.historyEntries.map { entry in
            Row(
                sequence: entry.sequence,
                projectedAt: entry.projectedAt,
                title: entry.card?.note?.primaryText ?? "This card is no longer available.",
                isCurrent: entry.persistentModelID == currentID
            )
        }

        guard let watermark else {
            upcoming = rows.sorted { $0.sequence < $1.sequence }
            past = []
            return
        }
        upcoming = rows.filter { $0.sequence >= watermark }.sorted { $0.sequence < $1.sequence }
        past = rows.filter { $0.sequence < watermark }.sorted { $0.sequence > $1.sequence }
    }

    static func load(deckID: PersistentIdentifier, from container: ModelContainer) throws -> ScheduleSnapshot {
        let context = ModelContext(container)
        guard let deck = context.model(for: deckID) as? Deck else {
            throw ScheduleSnapshotError.deckUnavailable
        }
        return ScheduleSnapshot(deck: deck)
    }

    func pastPage(limit: Int) -> [Row] {
        Array(past.prefix(max(0, limit)))
    }
}

enum ScheduleSnapshotError: Error {
    case deckUnavailable
}

struct DeckHistoryView: View {
    enum Tab: String, CaseIterable { case upcoming = "Upcoming"; case past = "Past" }

    let deck: Deck
    let scheduleRevision: Int
    @Environment(\.modelContext) private var modelContext
    @State private var tab: Tab = .upcoming
    @State private var pastLimit = DeckScheduler.queueSize
    @State private var snapshot: ScheduleSnapshot?

    init(deck: Deck, scheduleRevision: Int = 0) {
        self.deck = deck
        self.scheduleRevision = scheduleRevision
    }

    var body: some View {
        VStack {
            Picker("Schedule", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if let snapshot, !snapshot.isValid {
                unavailableView
            } else if let snapshot, tab == .upcoming {
                scheduleList(snapshot.upcoming, currentBadge: true)
            } else if let snapshot {
                List {
                    rows(snapshot.pastPage(limit: pastLimit), currentBadge: false)
                    if pastLimit < snapshot.past.count {
                        Button("Load More") { pastLimit += DeckScheduler.queueSize }
                    }
                }
            } else {
                ProgressView("Loading schedule…")
            }
        }
        .navigationTitle("Schedule")
        .task(id: scheduleRevision) {
            reloadSnapshot()
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "Schedule unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("Open the deck again after it refreshes.")
        )
    }

    private func reloadSnapshot() {
        do {
            snapshot = try ScheduleSnapshot.load(
                deckID: deck.persistentModelID,
                from: modelContext.container
            )
        } catch {
            snapshot = ScheduleSnapshot.invalid
        }
    }

    @ViewBuilder
    private func scheduleList(_ entries: [ScheduleSnapshot.Row], currentBadge: Bool) -> some View {
        if entries.isEmpty {
            ContentUnavailableView("No scheduled cards", systemImage: "calendar")
        } else {
            List { rows(entries, currentBadge: currentBadge) }
        }
    }

    @ViewBuilder
    private func rows(_ entries: [ScheduleSnapshot.Row], currentBadge: Bool) -> some View {
        ForEach(entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.title)
                    if currentBadge && entry.isCurrent {
                        Text("Current")
                            .font(.caption2)
                            .padding(4)
                            .background(.secondary.opacity(0.2), in: Capsule())
                    }
                }
                Text(entry.projectedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension ScheduleSnapshot {
    static let invalid = ScheduleSnapshot(isValid: false, upcoming: [], past: [])

    init(isValid: Bool, upcoming: [Row], past: [Row]) {
        self.isValid = isValid
        self.upcoming = upcoming
        self.past = past
    }
}
