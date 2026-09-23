import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

private final class MigrationFixtureBundleMarker {}

@MainActor
struct PreChangeStoreMigrationTests {
    private struct RetainedGraph: Equatable {
        let deckName: String
        let order: DisplayOrder
        let interval: Int
        let sleepEnabled: Bool
        let sleepStart: Int
        let sleepEnd: Int
        let fieldRoles: [String: FieldRole]
        let noteValues: [String]
        let cardID: Int64
        let history: [(Int, Date, Int64?)]
        let currentSequence: Int?
        let reachedSequence: Int?
        let nextSequence: Int

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.deckName == rhs.deckName && lhs.order == rhs.order &&
            lhs.interval == rhs.interval && lhs.sleepEnabled == rhs.sleepEnabled &&
            lhs.sleepStart == rhs.sleepStart && lhs.sleepEnd == rhs.sleepEnd &&
            lhs.fieldRoles == rhs.fieldRoles && lhs.noteValues == rhs.noteValues &&
            lhs.cardID == rhs.cardID && lhs.history.elementsEqual(rhs.history, by: { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }) &&
            lhs.currentSequence == rhs.currentSequence && lhs.reachedSequence == rhs.reachedSequence &&
            lhs.nextSequence == rhs.nextSequence
        }
    }

    @Test("complete 7f7df1d on-disk store opens, saves, and reopens without losing relationships")
    func oldStoreMigrates() throws {
        let bundle = Bundle(for: MigrationFixtureBundleMarker.self)
        let fixture = try #require(
            bundle.url(forResource: "PreChange7f7df1d", withExtension: "store", subdirectory: "Fixtures") ??
            bundle.url(forResource: "PreChange7f7df1d", withExtension: "store")
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = directory.appendingPathComponent("Flashcards.store")
        try FileManager.default.copyItem(at: fixture, to: store)

        let firstContainer = try SharedModelContainer.make(at: store)
        let firstContext = ModelContext(firstContainer)
        let before = try readGraph(in: firstContext)
        #expect(before.deckName == "Migration fixture")
        #expect(before.order == .random)
        #expect(before.interval == 45)
        #expect(before.sleepEnabled && before.sleepStart == 1320 && before.sleepEnd == 420)
        #expect(before.fieldRoles == ["Front": .primary, "Back": .secondary])
        #expect(before.noteValues == ["front", "back"])
        #expect(before.cardID == 1001)
        #expect(before.history.map(\.0) == [1, 2])
        #expect(before.currentSequence == 1 && before.reachedSequence == 1 && before.nextSequence == 3)

        let deck = try #require(firstContext.fetch(FetchDescriptor<Deck>()).first)
        deck.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try firstContext.save()

        let reopened = try SharedModelContainer.make(at: store)
        let after = try readGraph(in: ModelContext(reopened))
        #expect(after == before)
    }

    private func readGraph(in context: ModelContext) throws -> RetainedGraph {
        let deck = try #require(context.fetch(FetchDescriptor<Deck>()).first)
        let config = try #require(deck.displayConfig)
        let card = try #require(deck.cards.first)
        let note = try #require(card.note)
        let type = try #require(note.noteType)
        #expect(card.deck?.ankiDeckID == deck.ankiDeckID)
        #expect(type.notes.contains { $0.ankiNoteID == note.ankiNoteID })
        #expect(deck.historyEntries.allSatisfy { $0.deck?.ankiDeckID == deck.ankiDeckID })
        return RetainedGraph(
            deckName: deck.name,
            order: config.order,
            interval: config.intervalMinutes,
            sleepEnabled: config.sleepEnabled,
            sleepStart: config.sleepStartMinute,
            sleepEnd: config.sleepEndMinute,
            fieldRoles: Dictionary(uniqueKeysWithValues: type.fields.compactMap { field in
                field.role.map { (field.name, $0) }
            }),
            noteValues: note.fieldValues,
            cardID: card.ankiCardID,
            history: deck.historyEntries.sorted { $0.sequence < $1.sequence }.map { ($0.sequence, $0.projectedAt, $0.card?.ankiCardID) },
            currentSequence: deck.activeHistoryEntry?.sequence,
            reachedSequence: deck.highestReachedSequence,
            nextSequence: deck.nextHistorySequence
        )
    }
}
