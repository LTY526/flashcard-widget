import SwiftUI
import SwiftData

struct HistoryExpansionState {
    private(set) var expanded = Set<Int>()

    func contains(_ sequence: Int) -> Bool { expanded.contains(sequence) }
    mutating func toggle(_ sequence: Int) {
        if !expanded.insert(sequence).inserted { expanded.remove(sequence) }
    }
    mutating func reset() { expanded.removeAll() }
}

struct ScheduleSessionState {
    private(set) var snapshot: ScheduleSnapshot?
    private(set) var expansion = HistoryExpansionState()
    private(set) var revision: Int?
    private(set) var upcomingLimit = DeckScheduler.historyPageSize

    var visibleUpcoming: [ScheduleSnapshot.Row] {
        guard let snapshot else { return [] }
        return Array(snapshot.upcoming.prefix(upcomingLimit))
    }

    var hasMoreUpcoming: Bool {
        (snapshot?.upcoming.count ?? 0) > upcomingLimit
    }

    init(snapshot: ScheduleSnapshot? = nil, revision: Int? = nil) {
        self.snapshot = snapshot
        self.revision = revision
    }

    func needsReload(for revision: Int) -> Bool {
        snapshot == nil || self.revision != revision
    }

    mutating func begin(_ snapshot: ScheduleSnapshot, revision: Int) {
        self = ScheduleSessionState(snapshot: snapshot, revision: revision)
    }

    mutating func reloadIfNeeded(deckID: PersistentIdentifier, from container: ModelContainer,
                                 revision: Int) throws {
        guard needsReload(for: revision) else { return }
        try refresh(deckID: deckID, from: container, revision: revision)
    }

    mutating func refresh(deckID: PersistentIdentifier, from container: ModelContainer,
                          revision: Int) throws {
        let refreshed = try ScheduleSnapshot.load(deckID: deckID, from: container)
        begin(refreshed, revision: revision)
    }

    mutating func toggle(_ sequence: Int) { expansion.toggle(sequence) }

    mutating func loadMoreUpcoming() {
        guard let count = snapshot?.upcoming.count, upcomingLimit < count else { return }
        upcomingLimit = min(count, upcomingLimit + DeckScheduler.historyPageSize)
    }

    mutating func loadMore(deckID: PersistentIdentifier, from container: ModelContainer) throws {
        try snapshot?.loadMorePast(deckID: deckID, from: container)
    }
}

struct ScheduleEntrySnapshot {
    let snapshot: ScheduleSnapshot
    let revision: Int

    @MainActor
    static func load(deckID: PersistentIdentifier, ankiDeckID: Int64,
                     from container: ModelContainer, coordinator: PendingNextCoordinator,
                     revision: Int) throws -> ScheduleEntrySnapshot {
        let snapshot = try DeckScheduleEntry.load(deckID: deckID, ankiDeckID: ankiDeckID,
                                                  from: container, coordinator: coordinator)
        return ScheduleEntrySnapshot(snapshot: snapshot, revision: revision)
    }
}

/// Immutable values from one saved schedule session. Past uses descending
/// sequence keyset pages; the watermark never changes during an append.
struct ScheduleSnapshot {
    struct Row: Identifiable, Equatable {
        let sequence: Int
        let projectedAt: Date
        let primary: String?
        let secondary: String?
        let tertiary: String?
        let quaternary: String?
        let isCurrent: Bool

        var id: Int { sequence }
        var title: String { primary ?? "This card is no longer available." }
        var displayRoles: [String] {
            let roles = [primary, secondary, tertiary, quaternary].compactMap { text -> String? in
                guard let text, !text.isEmpty else { return nil }
                return text
            }
            return roles.isEmpty ? [title] : roles
        }

        init(entry: HistoryEntry, currentID: PersistentIdentifier?) {
            sequence = entry.sequence
            projectedAt = entry.projectedAt
            let note = entry.card?.note
            primary = note?.primaryText
            secondary = note?.secondaryText
            tertiary = note?.tertiaryText
            quaternary = note?.quaternaryText
            isCurrent = entry.persistentModelID == currentID
        }
    }

    let isValid: Bool
    let watermark: Int?
    let upcoming: [Row]
    private(set) var past: [Row]
    private(set) var hasMorePast: Bool
    var scheduleHorizon: Date? { upcoming.last.flatMap { $0.isCurrent ? nil : $0.projectedAt } }

    static func load(deckID: PersistentIdentifier, from container: ModelContainer) throws -> ScheduleSnapshot {
        let context = ModelContext(container)
        guard let deck = context.model(for: deckID) as? Deck else {
            throw ScheduleSnapshotError.deckUnavailable
        }
        let watermark = deck.highestReachedSequence
        let current = deck.activeHistoryEntry
        let valid: Bool
        switch (current, watermark) {
        case (nil, nil): valid = true
        case let (entry?, sequence?):
            valid = entry.sequence == sequence &&
                entry.deck?.persistentModelID == deckID &&
                DeckScheduler.isRenderable(entry)
        default: valid = false
        }
        guard valid else {
            return ScheduleSnapshot(isValid: false, watermark: watermark, upcoming: [], past: [], hasMorePast: false)
        }
        let future = try DeckScheduler.unreachedEntries(for: deck, in: context)
        guard future.count <= DeckScheduler.queueSize else {
            return ScheduleSnapshot(isValid: false, watermark: watermark, upcoming: [], past: [], hasMorePast: false)
        }
        let upcomingEntries = (current.map { [$0] } ?? []) + future
        let upcoming = upcomingEntries.map { Row(entry: $0, currentID: current?.persistentModelID) }
        let page = try pastPage(deckID: deckID, watermark: watermark, before: nil, in: context)
        return ScheduleSnapshot(isValid: true, watermark: watermark, upcoming: upcoming,
                                past: page.rows, hasMorePast: page.hasMore)
    }

    mutating func loadMorePast(deckID: PersistentIdentifier, from container: ModelContainer) throws {
        guard hasMorePast, let lowest = past.last?.sequence else { return }
        let page = try Self.pastPage(deckID: deckID, watermark: watermark, before: lowest,
                                     in: ModelContext(container))
        past.append(contentsOf: page.rows)
        hasMorePast = page.hasMore
    }

    func pastPage(limit: Int) -> [Row] { Array(past.prefix(max(0, limit))) }

    private static func pastPage(
        deckID: PersistentIdentifier, watermark: Int?, before: Int?, in context: ModelContext
    ) throws -> (rows: [Row], hasMore: Bool) {
        guard let watermark else { return ([], false) }
        let predicate: Predicate<HistoryEntry>
        if let before {
            predicate = #Predicate<HistoryEntry> { entry in
                entry.deck?.persistentModelID == deckID && entry.sequence < watermark && entry.sequence < before
            }
        } else {
            predicate = #Predicate<HistoryEntry> { entry in
                entry.deck?.persistentModelID == deckID && entry.sequence < watermark
            }
        }
        var descriptor = FetchDescriptor<HistoryEntry>(predicate: predicate,
            sortBy: [SortDescriptor(\HistoryEntry.sequence, order: .reverse)])
        descriptor.fetchLimit = DeckScheduler.historyPageSize + 1
        let entries = try ScheduleQueryTrace.fetch(descriptor, in: context,
                                                   kind: .past(watermark: watermark, before: before))
        return (Array(entries.prefix(DeckScheduler.historyPageSize)).map { Row(entry: $0, currentID: nil) },
                entries.count > DeckScheduler.historyPageSize)
    }
}

enum ScheduleSnapshotError: Error {
    case deckUnavailable
}

/// This is the Schedule entry path: pending Next work must commit before the
/// value snapshot is loaded from a fresh context.
@MainActor
enum DeckScheduleEntry {
    static func load(
        deckID: PersistentIdentifier,
        ankiDeckID: Int64,
        from container: ModelContainer,
        coordinator: PendingNextCoordinator
    ) throws -> ScheduleSnapshot {
        try coordinator.flush(deckIDs: [ankiDeckID])
        return try ScheduleSnapshot.load(deckID: deckID, from: container)
    }
}

struct DeckHistoryView: View {
    enum Tab: String, CaseIterable { case upcoming = "Upcoming"; case past = "Past" }

    let deck: Deck
    let scheduleRevision: Int
    @Environment(\.modelContext) private var modelContext
    @Binding var tab: Tab
    @State private var session: ScheduleSessionState

    init(deck: Deck, tab: Binding<Tab>, initialSnapshot: ScheduleSnapshot? = nil,
         initialRevision: Int? = nil, scheduleRevision: Int = 0) {
        self.deck = deck
        self._tab = tab
        self._session = State(initialValue: ScheduleSessionState(snapshot: initialSnapshot,
                                                                  revision: initialRevision))
        self.scheduleRevision = scheduleRevision
    }

    var body: some View {
        let snapshot = session.snapshot
        VStack {
            Picker("Schedule", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if let snapshot, !snapshot.isValid {
                unavailableView
            } else if let snapshot, tab == .upcoming {
                scheduleList(session.visibleUpcoming, currentBadge: true)
            } else if let snapshot {
                List {
                    pastRows(snapshot.past)
                    if snapshot.hasMorePast {
                        Button("Load More") { loadMorePast() }
                    }
                }
            } else {
                ProgressView("Loading schedule…")
            }
        }
        .navigationTitle("Schedule")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { reloadSnapshot() }
        }
        .task(id: scheduleRevision) {
            reloadIfNeeded()
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "Schedule unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("Open the deck again after it refreshes.")
        )
    }

    private func reloadIfNeeded() {
        do {
            try session.reloadIfNeeded(deckID: deck.persistentModelID,
                                       from: modelContext.container, revision: scheduleRevision)
        } catch {
            session.begin(ScheduleSnapshot.invalid, revision: scheduleRevision)
        }
    }

    private func reloadSnapshot() {
        do {
            try session.refresh(deckID: deck.persistentModelID,
                                from: modelContext.container, revision: scheduleRevision)
        } catch {
            session.begin(ScheduleSnapshot.invalid, revision: scheduleRevision)
        }
    }

    private func loadMorePast() {
        do { try session.loadMore(deckID: deck.persistentModelID, from: modelContext.container) }
        catch { session.begin(ScheduleSnapshot.invalid, revision: scheduleRevision) }
    }

    @ViewBuilder
    private func pastRows(_ entries: [ScheduleSnapshot.Row]) -> some View {
        ForEach(entries) { entry in
            Button {
                session.toggle(entry.sequence)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if session.expansion.contains(entry.sequence) {
                        ForEach(Array(entry.displayRoles.enumerated()), id: \.offset) { _, role in
                            Text(role).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(entry.title)
                    }
                    Text(entry.projectedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func scheduleList(_ entries: [ScheduleSnapshot.Row], currentBadge: Bool) -> some View {
        if entries.isEmpty {
            ContentUnavailableView("No future schedule", systemImage: "calendar")
        } else {
            List {
                rows(entries, currentBadge: currentBadge)
                if session.hasMoreUpcoming {
                    Button("Load More") { session.loadMoreUpcoming() }
                        .accessibilityLabel("Load more upcoming cards")
                }
                if let horizon = session.snapshot?.scheduleHorizon {
                    Text("Scheduled until \(horizon.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("No future schedule")
                }
            }
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
    static let invalid = ScheduleSnapshot(isValid: false, watermark: nil, upcoming: [], past: [], hasMorePast: false)
}
