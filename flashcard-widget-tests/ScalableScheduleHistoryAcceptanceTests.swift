import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

@MainActor
@Suite("scalable schedule history", .serialized)
struct ScalableScheduleHistoryAcceptanceTests {
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
        var pastQueries: [(ScheduleQueryTrace.Kind, Int)] = []
        ScheduleQueryTrace.observe = { kind, limit in
            if case .past = kind { pastQueries.append((kind, limit)) }
        }
        defer { ScheduleQueryTrace.observe = nil }
        var snapshot = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(pastQueries.count == (pastCount == 0 ? 0 : 1))
        if pastCount > 0 {
            #expect(pastQueries[0].0 == .past(watermark: pastCount + 1, before: nil))
            #expect(pastQueries[0].1 == 21)
        }
        #expect(snapshot.past.count == min(20, pastCount))
        #expect(snapshot.past.map(\.sequence) == Array((1...max(1, pastCount)).reversed().prefix(min(20, pastCount))))
        #expect(snapshot.hasMorePast == (pastCount > 20))
        let firstPage = snapshot.past
        if pastCount > 20 {
            try snapshot.loadMorePast(deckID: deckID, from: container)
            #expect(pastQueries.count == 2)
            #expect(pastQueries[1].0 == .past(watermark: pastCount + 1, before: pastCount - 19))
            #expect(pastQueries[1].1 == 21)
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
        // A saved change and subsection selection leave the live session intact.
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
        let reentered = ScheduleSessionState(snapshot: try ScheduleSnapshot.load(deckID: deckID, from: container), revision: 1)
        #expect(!reentered.needsReload(for: 1))
        #expect(reentered.snapshot?.past.count == 20)
    }

    @Test("the saved entry revision is checked against activation before accepting an initial snapshot")
    func staleInitialSnapshotNeedsActivationReload() throws {
        let (container, deckID, _) = try fixture(pastCount: 1)
        let entered = ScheduleEntrySnapshot(
            snapshot: try ScheduleSnapshot.load(deckID: deckID, from: container), revision: 0)
        let rebuiltChild = ScheduleSessionState(snapshot: entered.snapshot, revision: entered.revision)
        #expect(rebuiltChild.needsReload(for: 1))
        #expect(!rebuiltChild.needsReload(for: 0))
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

    @Test(arguments: [0, 3_000])
    func schedulerAndSelectorUseBoundedQueue(pastCount: Int) throws {
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

        var queries: [(ScheduleQueryTrace.Kind, Int)] = []
        ScheduleQueryTrace.observe = { queries.append(($0, $1)) }
        defer { ScheduleQueryTrace.observe = nil }

        guard case .cards(let selected) = ScheduleSelector.select(deck: deck, now: start) else {
            Issue.record("Expected a valid widget selection")
            return
        }
        #expect(selected.map(\.sequence) == Array(currentSequence...(currentSequence + 4)))
        #expect(queries.allSatisfy { $0.1 <= DeckScheduler.queueSize + 1 })
        queries.removeAll()

        _ = try DeckScheduler.reconcileOnActivation(in: container, now: start.addingTimeInterval(900))
        #expect(queries.contains { $0.0 == .unreached && $0.1 == 101 })
        #expect(queries.allSatisfy { $0.1 <= 101 })
        queries.removeAll()

        let writer = ModelContext(container)
        let savedDeck = try #require(writer.model(for: deck.persistentModelID) as? Deck)
        try DeckScheduler.advanceImmediately(savedDeck, in: writer, now: start.addingTimeInterval(901))
        #expect(savedDeck.highestReachedSequence == currentSequence + 2)
        try DeckScheduler.rebuildFuture(for: savedDeck, in: writer, now: start.addingTimeInterval(901))
        let rebuilt = try DeckScheduler.validatedUnreachedEntries(for: savedDeck, in: writer)
        #expect(rebuilt.count == DeckScheduler.queueSize)
        #expect(rebuilt.first?.sequence == currentSequence + 3)
        #expect(rebuilt.last?.sequence == currentSequence + 102)
        #expect(queries.contains { $0.0 == .current(sequence: currentSequence + 2) && $0.1 == 1 })
        #expect(queries.allSatisfy { $0.1 <= 101 })
        try writer.save()
        let verify = ModelContext(container)
        let persisted = try #require(verify.model(for: deck.persistentModelID) as? Deck)
        #expect(try DeckScheduler.validatedUnreachedEntries(for: persisted, in: verify).count == 100)
        #expect(try ScheduleSnapshot.load(deckID: deck.persistentModelID, from: container).past.first?.sequence == currentSequence + 1)
        let oversized = HistoryEntry(sequence: currentSequence + 103,
            projectedAt: start.addingTimeInterval(100_000), card: persisted.activeHistoryEntry?.card, deck: persisted)
        verify.insert(oversized)
        #expect(throws: ScheduleError.malformed) {
            try DeckScheduler.validatedUnreachedEntries(for: persisted, in: verify)
        }
        #expect(ScheduleSelector.select(deck: persisted, now: start) == .brokenSchedule)
    }
}
