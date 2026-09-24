import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

@MainActor
@Suite("scalable schedule history", .serialized)
struct ScalableScheduleHistoryAcceptanceTests {
    private enum InjectedFetchError: Error { case unavailable }
    private struct QueryShape: Equatable {
        let kind: String
        let limit: Int
        let count: Int
    }

    private func shape(_ events: [ScheduleQueryTrace.Event], currentSequence: Int) -> [QueryShape] {
        events.map { event in
            let kind: String
            switch event.kind {
            case .unreached: kind = "unreached"
            case .current(let sequence): kind = "current+\(sequence - currentSequence)"
            case .past(let watermark, let before):
                kind = "past+\(watermark - currentSequence):\(before.map { $0 - currentSequence } ?? -1)"
            }
            return QueryShape(kind: kind, limit: event.fetchLimit, count: event.returnedCount)
        }
    }

    private func fixture(pastCount: Int) throws -> (ModelContainer, PersistentIdentifier, Date) {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let deck = Deck(ankiDeckID: 99, name: "History")
        context.insert(deck)
        let noteType = NoteType(ankiNoteTypeID: 99, name: "Basic")
        let field = NoteTypeField(name: "Front", ordinal: 0, role: .primary)
        field.noteType = noteType
        let note = Note(ankiNoteID: 99, fieldValues: ["Current"], noteType: noteType)
        let card = Card(ankiCardID: 99, ordinal: 0, note: note, deck: deck)
        context.insert(noteType)
        context.insert(field)
        context.insert(note)
        context.insert(card)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        if pastCount > 0 {
            for sequence in 1...(pastCount + 1) {
                let entry = HistoryEntry(sequence: sequence, projectedAt: start,
                                         card: sequence == pastCount + 1 ? card : nil, deck: deck)
                context.insert(entry)
                if sequence == pastCount + 1 { deck.activeHistoryEntry = entry }
            }
            deck.highestReachedSequence = pastCount + 1
        }
        try context.save()
        return (container, deck.persistentModelID, start)
    }

    @Test(arguments: [0, 1, 20, 21, 420])
    func boundedPagesAndStableSession(pastCount: Int) throws {
        let (container, deckID, _) = try fixture(pastCount: pastCount)
        var pastQueries: [ScheduleQueryTrace.Event] = []
        ScheduleQueryTrace.observeFetch = { event in
            if case .past = event.kind { pastQueries.append(event) }
        }
        defer { ScheduleQueryTrace.observeFetch = nil }
        var snapshot = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(pastQueries.count == (pastCount == 0 ? 0 : 1))
        if pastCount > 0 {
            #expect(pastQueries[0].kind == .past(watermark: pastCount + 1, before: nil))
            #expect(pastQueries[0].fetchLimit == 21)
        }
        #expect(snapshot.past.count == min(20, pastCount))
        #expect(snapshot.past.map(\.sequence) == Array((1...max(1, pastCount)).reversed().prefix(min(20, pastCount))))
        #expect(snapshot.hasMorePast == (pastCount > 20))
        let firstPage = snapshot.past
        if pastCount > 20 {
            try snapshot.loadMorePast(deckID: deckID, from: container)
            #expect(pastQueries.count == 2)
            #expect(pastQueries[1].kind == .past(watermark: pastCount + 1, before: pastCount - 19))
            #expect(pastQueries[1].fetchLimit == 21)
            #expect(snapshot.past.count == min(40, pastCount))
            #expect(Array(snapshot.past.prefix(20)) == firstPage)
            #expect(Set(snapshot.past.map(\.sequence)).count == snapshot.past.count)
        }
        let writer = ModelContext(container)
        let deck = try #require(writer.model(for: deckID) as? Deck)
        let nextSequence = (deck.highestReachedSequence ?? 0) + 1
        let newlyCurrent = HistoryEntry(sequence: nextSequence, projectedAt: .now,
                                        card: deck.activeHistoryEntry?.card ?? deck.cards.first, deck: deck)
        writer.insert(newlyCurrent)
        deck.activeHistoryEntry = newlyCurrent
        deck.highestReachedSequence = nextSequence
        try writer.save()
        #expect(snapshot.past.prefix(firstPage.count).map(\.sequence) == firstPage.map(\.sequence))
        #expect(snapshot.watermark == (pastCount == 0 ? nil : pastCount + 1))
        let refreshed = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(refreshed.watermark == nextSequence)
        if pastCount > 0 { #expect(refreshed.past.first?.sequence == nextSequence - 1) }
    }

    @Test("new fetch reflects four mapped roles while an existing page remains immutable")
    func mappedRolesAndMissingCard() throws {
        let (container, deckID, _) = try fixture(pastCount: 2)
        let writer = ModelContext(container)
        let deck = try #require(writer.model(for: deckID) as? Deck)
        let noteType = try #require(deck.activeHistoryEntry?.card?.note?.noteType)
        let note = try #require(deck.activeHistoryEntry?.card?.note)
        for (ordinal, role) in [(1, FieldRole.secondary), (2, .tertiary), (3, .quaternary)] {
            let field = NoteTypeField(name: "Field \(ordinal)", ordinal: ordinal, role: role)
            field.noteType = noteType
            writer.insert(field)
        }
        note.fieldValues = ["Primary", "Secondary", "Tertiary", "Quaternary"]
        let past = try #require(try DeckScheduler.entry(sequence: 2, for: deck, in: writer))
        past.card = deck.activeHistoryEntry?.card
        try writer.save()

        let original = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(original.past.first?.displayRoles == ["Primary", "Secondary", "Tertiary", "Quaternary"])
        #expect(original.past.last?.title == "This card is no longer available.")
        #expect(original.past.last?.displayRoles == ["This card is no longer available."])
        note.fieldValues[0] = "Edited"
        try writer.save()
        let refreshed = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(original.past.first?.primary == "Primary")
        #expect(refreshed.past.first?.primary == "Edited")
    }

    @Test("expansion persists across append and resets for a new session; horizon uses last future")
    func expansionAndHorizon() throws {
        let (container, deckID, _) = try fixture(pastCount: 21)
        var session = ScheduleSessionState(snapshot: try ScheduleSnapshot.load(deckID: deckID, from: container), revision: 0)
        #expect(!session.needsReload(for: 0))
        session.toggle(20)
        #expect(session.expansion.contains(20))
        try session.loadMore(deckID: deckID, from: container)
        #expect(session.snapshot?.past.count == 21)
        #expect(session.expansion.contains(20))
        session.toggle(20)
        #expect(!session.expansion.contains(20))
        session.toggle(20)

        let writer = ModelContext(container)
        let deck = try #require(writer.model(for: deckID) as? Deck)
        let next = HistoryEntry(sequence: 23, projectedAt: .now, card: deck.activeHistoryEntry?.card, deck: deck)
        writer.insert(next)
        deck.activeHistoryEntry = next
        deck.highestReachedSequence = 23
        try writer.save()
        var route = DeckDetailRoute()
        route.open(99)
        route.select(.schedule)
        route.scheduleTab = .past
        route.scheduleTab = .upcoming
        route.scheduleTab = .past
        // A saved change and subsection selection leave the live session intact.
        #expect(route.scheduleTab == .past)
        #expect(session.snapshot?.watermark == 22)
        #expect(session.snapshot?.past.count == 21)
        #expect(session.expansion.contains(20))

        // Refresh, activation, and re-entry all begin a freshly loaded session.
        #expect(session.needsReload(for: 1))
        try session.reloadIfNeeded(deckID: deckID, from: container, revision: 1)
        #expect(session.snapshot?.watermark == 23)
        #expect(session.snapshot?.past.count == 20)
        #expect(!session.expansion.contains(20))
        #expect(session.snapshot?.scheduleHorizon == nil)
        #expect(!session.needsReload(for: 1))

        session.toggle(22)
        try session.refresh(deckID: deckID, from: container, revision: 1)
        #expect(!session.expansion.contains(22))
        #expect(session.snapshot?.past.count == 20)
        let entry = try ScheduleEntrySnapshot.load(deckID: deckID, ankiDeckID: 99,
            from: container, coordinator: PendingNextCoordinator(), revision: 1)
        let reentered = ScheduleSessionState(snapshot: entry.snapshot, revision: entry.revision)
        #expect(!reentered.needsReload(for: 1))
        #expect(reentered.snapshot?.past.count == 20)
    }

    @Test("the saved entry revision is checked against activation before accepting an initial snapshot")
    func staleInitialSnapshotNeedsActivationReload() throws {
        let (container, deckID, _) = try fixture(pastCount: 1)
        let entered = try ScheduleEntrySnapshot.load(deckID: deckID, ankiDeckID: 99,
            from: container, coordinator: PendingNextCoordinator(), revision: 0)
        var rebuiltChild = ScheduleSessionState(snapshot: entered.snapshot, revision: entered.revision)
        #expect(rebuiltChild.needsReload(for: 1))
        #expect(!rebuiltChild.needsReload(for: 0))
        var queries: [ScheduleQueryTrace.Event] = []
        ScheduleQueryTrace.observeFetch = { queries.append($0) }
        defer { ScheduleQueryTrace.observeFetch = nil }
        try rebuiltChild.reloadIfNeeded(deckID: deckID, from: container, revision: 0)
        #expect(queries.isEmpty, "an entry snapshot at the current revision is not fetched twice")
        try rebuiltChild.reloadIfNeeded(deckID: deckID, from: container, revision: 1)
        #expect(queries.contains { if case .past = $0.kind { true } else { false } })
        #expect(rebuiltChild.revision == 1)
    }

    @Test("Past page instrumentation records completed bounded fetches")
    func completedPastFetches() throws {
        let (container, deckID, _) = try fixture(pastCount: 21)
        var events: [ScheduleQueryTrace.Event] = []
        ScheduleQueryTrace.observeFetch = { events.append($0) }
        defer { ScheduleQueryTrace.observeFetch = nil }
        var snapshot = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(events.filter { if case .past = $0.kind { true } else { false } }.count == 1)
        #expect(events.last?.kind == .past(watermark: 22, before: nil))
        #expect(events.last?.fetchLimit == 21)
        #expect(events.last?.returnedCount == 21)
        try snapshot.loadMorePast(deckID: deckID, from: container)
        #expect(events.last?.kind == .past(watermark: 22, before: 2))
        #expect(events.last?.fetchLimit == 21)
        #expect(events.last?.returnedCount == 1)
    }

    @Test("a failed queue fetch aborts pause and future rebuild before deletion")
    func failedQueueFetchDoesNotMutate() throws {
        let (container, deckID, start) = try fixture(pastCount: 1)
        let context = ModelContext(container)
        let deck = try #require(context.model(for: deckID) as? Deck)
        deck.nextHistorySequence = 3
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        try context.save()
        let before = try DeckScheduler.validatedUnreachedEntries(for: deck, in: context).map(\.persistentModelID)
        let originalSequence = deck.nextHistorySequence

        ScheduleQueryTrace.failBeforeFetch = { kind in
            if kind == .unreached { throw InjectedFetchError.unavailable }
        }
        defer { ScheduleQueryTrace.failBeforeFetch = nil }
        #expect(throws: InjectedFetchError.self) {
            try DeckScheduler.setPaused(true, deck: deck, in: context, now: start)
        }
        #expect(!deck.isPaused)
        #expect(deck.nextHistorySequence == originalSequence)
        #expect(throws: InjectedFetchError.self) {
            try DeckScheduler.rebuildFuture(for: deck, in: context, now: start)
        }
        #expect(throws: InjectedFetchError.self) {
            try DeckScheduler.handleOrderChange(for: deck, in: context)
        }
        #expect(throws: InjectedFetchError.self) {
            try DeckScheduler.handleSoftDelete(for: deck, in: context)
        }
        #expect(deck.nextHistorySequence == originalSequence)
        ScheduleQueryTrace.failBeforeFetch = nil
        #expect(try DeckScheduler.validatedUnreachedEntries(for: deck, in: context).map(\.persistentModelID) == before)
    }

    @Test("scheduler and Past query shapes stay bounded as history grows")
    func schedulerAndSelectorUseBoundedQueue() throws {
        let emptyHistory = try exerciseScheduler(pastCount: 0)
        let mediumHistory = try exerciseScheduler(pastCount: 420)
        let largeHistory = try exerciseScheduler(pastCount: 3_000)
        #expect(Array(emptyHistory.prefix(4)) == Array(largeHistory.prefix(4)))
        #expect(Array(mediumHistory.suffix(2)) == Array(largeHistory.suffix(2)))
    }

    private func exerciseScheduler(pastCount: Int) throws -> [[QueryShape]] {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let deck = Deck(ankiDeckID: 500 + Int64(pastCount), name: "Large history")
        let noteType = NoteType(ankiNoteTypeID: 500 + Int64(pastCount), name: "Basic")
        let field = NoteTypeField(name: "Front", ordinal: 0, role: .primary)
        field.noteType = noteType
        let note = Note(ankiNoteID: 500 + Int64(pastCount), fieldValues: ["Card"], noteType: noteType)
        let card = Card(ankiCardID: 500 + Int64(pastCount), ordinal: 0, note: note, deck: deck)
        let config = DisplayConfig(order: .sequential, intervalMinutes: 15)
        config.deck = deck
        deck.displayConfig = config
        context.insert(deck)
        context.insert(noteType)
        context.insert(field)
        context.insert(note)
        context.insert(card)
        context.insert(config)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        if pastCount > 0 {
            for sequence in 1...pastCount {
                context.insert(HistoryEntry(sequence: sequence, projectedAt: start, card: nil, deck: deck))
            }
        }
        let currentSequence = pastCount + 1
        let current = HistoryEntry(sequence: currentSequence, projectedAt: start, card: card, deck: deck)
        context.insert(current)
        deck.activeHistoryEntry = current
        deck.highestReachedSequence = currentSequence
        for offset in 1...DeckScheduler.queueSize {
            context.insert(HistoryEntry(sequence: currentSequence + offset,
                projectedAt: start.addingTimeInterval(TimeInterval(offset * 900)), card: card, deck: deck))
        }
        deck.nextHistorySequence = currentSequence + DeckScheduler.queueSize + 1
        try context.save()
        #expect(try ScheduleSnapshot.load(deckID: deck.persistentModelID, from: container).scheduleHorizon ==
            start.addingTimeInterval(TimeInterval(DeckScheduler.queueSize * 900)))

        var queries: [ScheduleQueryTrace.Event] = []
        ScheduleQueryTrace.observeFetch = { queries.append($0) }
        defer { ScheduleQueryTrace.observeFetch = nil }
        var phases: [[QueryShape]] = []

        guard case .cards(let selected) = ScheduleSelector.select(deck: deck, now: start) else {
            Issue.record("Expected a valid widget selection")
            return []
        }
        #expect(selected.map(\.sequence) == Array(currentSequence...(currentSequence + 4)))
        #expect(shape(queries, currentSequence: currentSequence) == [
            QueryShape(kind: "unreached", limit: 101, count: 100)
        ])
        phases.append(shape(queries, currentSequence: currentSequence))
        queries.removeAll()

        _ = try DeckScheduler.reconcileOnActivation(in: container, now: start.addingTimeInterval(900))
        #expect(shape(queries, currentSequence: currentSequence) == [
            QueryShape(kind: "unreached", limit: 101, count: 100)
        ])
        phases.append(shape(queries, currentSequence: currentSequence))
        queries.removeAll()

        let writer = ModelContext(container)
        let savedDeck = try #require(writer.model(for: deck.persistentModelID) as? Deck)
        try DeckScheduler.advanceImmediately(savedDeck, in: writer, now: start.addingTimeInterval(901))
        #expect(savedDeck.highestReachedSequence == currentSequence + 2)
        #expect(shape(queries, currentSequence: currentSequence) == [
            QueryShape(kind: "unreached", limit: 101, count: 100),
            QueryShape(kind: "current+2", limit: 1, count: 1)
        ])
        phases.append(shape(queries, currentSequence: currentSequence))
        queries.removeAll()
        try DeckScheduler.rebuildFuture(for: savedDeck, in: writer, now: start.addingTimeInterval(901))
        #expect(shape(queries, currentSequence: currentSequence) == [
            QueryShape(kind: "unreached", limit: 101, count: 99),
            QueryShape(kind: "unreached", limit: 101, count: 1)
        ])
        phases.append(shape(queries, currentSequence: currentSequence))
        queries.removeAll()
        let rebuilt = try DeckScheduler.validatedUnreachedEntries(for: savedDeck, in: writer)
        #expect(rebuilt.count == DeckScheduler.queueSize)
        #expect(rebuilt.first?.sequence == currentSequence + 3)
        #expect(rebuilt.last?.sequence == currentSequence + 102)
        #expect(shape(queries, currentSequence: currentSequence) == [
            QueryShape(kind: "unreached", limit: 101, count: 100)
        ])
        queries.removeAll()
        try writer.save()
        let verify = ModelContext(container)
        let persisted = try #require(verify.model(for: deck.persistentModelID) as? Deck)
        #expect(try DeckScheduler.validatedUnreachedEntries(for: persisted, in: verify).count == 100)
        queries.removeAll()
        var snapshot = try ScheduleSnapshot.load(deckID: deck.persistentModelID, from: container)
        #expect(queries.count == 2)
        #expect(shape(queries, currentSequence: currentSequence).first ==
            QueryShape(kind: "unreached", limit: 101, count: 100))
        #expect(queries.last?.kind == .past(watermark: currentSequence + 2, before: nil))
        #expect(queries.last?.fetchLimit == 21)
        #expect(queries.last?.returnedCount == min(21, pastCount + 2))
        #expect(snapshot.past.first?.sequence == currentSequence + 1)
        phases.append([QueryShape(kind: "first-past", limit: queries.last?.fetchLimit ?? .max,
                                  count: queries.filter {
                                      if case .past = $0.kind { true } else { false }
                                  }.count)])
        if pastCount > 20 {
            queries.removeAll()
            try snapshot.loadMorePast(deckID: deck.persistentModelID, from: container)
            #expect(queries.count == 1)
            #expect(queries[0].kind == .past(watermark: currentSequence + 2,
                                             before: currentSequence - 18))
            #expect(queries[0].fetchLimit == 21)
            #expect(queries[0].returnedCount == 21)
            phases.append([QueryShape(kind: "next-past", limit: queries[0].fetchLimit,
                                      count: queries.count)])
        }
        let oversized = HistoryEntry(sequence: currentSequence + 103,
            projectedAt: start.addingTimeInterval(100_000), card: persisted.activeHistoryEntry?.card, deck: persisted)
        verify.insert(oversized)
        #expect(throws: ScheduleError.malformed) {
            try DeckScheduler.validatedUnreachedEntries(for: persisted, in: verify)
        }
        #expect(ScheduleSelector.select(deck: persisted, now: start) == .brokenSchedule)
        #expect(throws: ScheduleError.malformed) {
            try DeckScheduler.setPaused(true, deck: persisted, in: verify, now: start)
        }
        #expect(!persisted.isPaused)
        return phases
    }
}
