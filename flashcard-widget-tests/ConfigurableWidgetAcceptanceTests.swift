import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

@MainActor
@Suite("configurable Lock Screen widget acceptance")
struct ConfigurableWidgetAcceptanceTests {
    private func fixture() throws -> (ModelContext, Deck) {
        let schema = SharedModelContainer.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let deck = Deck(ankiDeckID: 42, name: "Biology")
        let noteType = NoteType(ankiNoteTypeID: 1, name: "Basic")
        let front = NoteTypeField(name: "Front", ordinal: 0, role: .primary)
        front.noteType = noteType
        let back = NoteTypeField(name: "Back", ordinal: 1, role: .secondary)
        back.noteType = noteType
        let note = Note(ankiNoteID: 1, fieldValues: ["Cell", "Basic unit of life"], noteType: noteType)
        let card = Card(ankiCardID: 1, ordinal: 0, note: note, deck: deck)
        let config = DisplayConfig(order: .sequential, intervalMinutes: 15)
        config.deck = deck
        deck.displayConfig = config
        context.insert(deck)
        context.insert(noteType)
        context.insert(front)
        context.insert(back)
        context.insert(note)
        context.insert(card)
        context.insert(config)
        try context.save()
        return (context, deck)
    }

    @Test("initial seed persists a current card plus 100 future entries")
    func initialQueueUsesInjectedNow() throws {
        let (context, deck) = try fixture()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: now)
        let entries = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        #expect(entries.count == DeckScheduler.queueSize + 1)
        #expect(deck.activeHistoryEntry?.sequence == 1)
        #expect(deck.highestReachedSequence == 1)
        #expect(entries.first?.projectedAt == now)
        #expect(entries.last?.projectedAt == now.addingTimeInterval(TimeInterval(DeckScheduler.queueSize * 15 * 60)))
    }

    @Test("selector advances through due prefix and emits no more than five cards")
    func selectorUsesDuePrefix() throws {
        let (context, deck) = try fixture()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let result = ScheduleSelector.select(deck: deck, now: start.addingTimeInterval(2 * 15 * 60))
        guard case .cards(let cards) = result else {
            Issue.record("Expected cards, got \(result)")
            return
        }
        #expect(cards.map(\.sequence) == [3, 4, 5, 6, 7])
        #expect(cards.first?.date == start.addingTimeInterval(2 * 15 * 60))
    }

    @Test("malformed duplicate sequence is broken and reconciliation is mutation-free")
    func malformedScheduleDoesNotMutate() throws {
        let (context, deck) = try fixture()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: now)
        deck.historyEntries[1].sequence = deck.historyEntries[0].sequence
        let before = deck.historyEntries.map { ($0.sequence, $0.projectedAt) }
        #expect(ScheduleSelector.select(deck: deck, now: now) == .brokenSchedule)
        #expect(throws: ScheduleError.malformed) {
            try DeckScheduler.reconcile(deck, in: context, now: now)
        }
        let after = deck.historyEntries.map { ($0.sequence, $0.projectedAt) }
        #expect(before.elementsEqual(after, by: ==))
    }

    @Test("sequence overflow is classified without trapping or mutation")
    func sequenceOverflowIsMalformed() throws {
        let (context, deck) = try fixture()
        deck.highestReachedSequence = Int.max
        deck.nextHistorySequence = Int.max
        let before = deck.historyEntries.count

        #expect(ScheduleSelector.select(deck: deck, now: .now) == .brokenSchedule)
        #expect(throws: ScheduleError.malformed) {
            try DeckScheduler.ensureSchedule(for: deck, in: context, now: .now)
        }
        #expect(deck.historyEntries.count == before)
        #expect(deck.nextHistorySequence == Int.max)
    }

    @Test("pause clears only unreached rows and resume advances current at injected now")
    func pauseAndResumeQueueSemantics() throws {
        let (context, deck) = try fixture()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        try DeckScheduler.reconcile(deck, in: context, now: start)

        try DeckScheduler.setPaused(true, deck: deck, in: context, now: start)
        #expect(deck.isPaused)
        #expect(deck.historyEntries.count == 1)
        #expect(deck.historyEntries.first?.sequence == 1)

        let resumedAt = start.addingTimeInterval(3_600)
        try DeckScheduler.setPaused(false, deck: deck, in: context, now: resumedAt)
        #expect(deck.activeHistoryEntry?.sequence == 2)
        #expect(deck.activeHistoryEntry?.projectedAt == resumedAt)
        #expect(deck.highestReachedSequence == 2)
        let unreached = deck.historyEntries
            .filter { $0.sequence > (deck.highestReachedSequence ?? 0) }
            .sorted { $0.sequence < $1.sequence }
        #expect(unreached.count == DeckScheduler.queueSize)
        #expect(unreached.first?.sequence == 3)
        #expect(unreached.first?.projectedAt == resumedAt.addingTimeInterval(15 * 60))
    }

    @Test("Next reconciles overdue entries before advancing once")
    func nextReconcilesBeforeAdvancing() throws {
        let (context, deck) = try fixture()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let now = start.addingTimeInterval(2 * 15 * 60)

        try DeckScheduler.next(deck, in: context, now: now)

        #expect(deck.highestReachedSequence == 4)
        #expect(deck.activeHistoryEntry?.sequence == 4)
        #expect(deck.activeHistoryEntry?.projectedAt == now)
        let later = deck.historyEntries
            .filter { $0.sequence > 4 }
            .sorted { $0.sequence < $1.sequence }
        #expect(later.first?.projectedAt == now.addingTimeInterval(15 * 60))
        #expect(later.count == DeckScheduler.queueSize)
    }

    @Test("rapid Next advances immediately and defers the full queue rebuild")
    func immediateAdvanceDefersFutureRebuild() throws {
        let (context, deck) = try fixture()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let before = Dictionary(uniqueKeysWithValues: deck.historyEntries
            .filter { $0.sequence > 2 }
            .map { ($0.sequence, $0.projectedAt) })
        let tappedAt = start.addingTimeInterval(60)

        try DeckScheduler.advanceImmediately(deck, in: context, now: tappedAt)

        #expect(deck.activeHistoryEntry?.sequence == 2)
        #expect(deck.activeHistoryEntry?.projectedAt == tappedAt)
        let deferredFuture = deck.historyEntries.filter { $0.sequence > 2 }
        #expect(deferredFuture.count == DeckScheduler.queueSize - 1)
        #expect(deferredFuture.allSatisfy { before[$0.sequence] == $0.projectedAt })

        try DeckScheduler.rebuildFuture(for: deck, in: context, now: tappedAt)
        let rebuilt = deck.historyEntries
            .filter { $0.sequence > 2 }
            .sorted { $0.sequence < $1.sequence }
        #expect(rebuilt.count == DeckScheduler.queueSize)
        #expect(rebuilt.first?.projectedAt == tappedAt.addingTimeInterval(15 * 60))
    }

    @Test("deep link grammar is canonical")
    func deepLinkGrammar() {
        #expect(DeckDeepLink.parse(URL(string: "flashcard-widget://deck/0")!) == 0)
        #expect(DeckDeepLink.parse(URL(string: "flashcard-widget://deck/123456789")!) == 123456789)
        for raw in ["-1", "+1", "01", "9223372036854775808", "1/", " 1"] {
            #expect(DeckDeepLink.parse(URL(string: "flashcard-widget://deck/\(raw)")!) == nil)
        }
        #expect(DeckDeepLink.parse(URL(string: "flashcard-widget://deck/1?q=x")!) == nil)
        #expect(DeckDeepLink.parse(URL(string: "flashcard-widget://deck/1#x")!) == nil)
    }
}
