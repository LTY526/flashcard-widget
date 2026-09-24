import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

@MainActor
@Suite("scalable schedule history")
struct ScalableScheduleHistoryAcceptanceTests {
    private func fixture(pastCount: Int) throws -> (ModelContainer, PersistentIdentifier, Date) {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let deck = Deck(ankiDeckID: 99, name: "History")
        context.insert(deck)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for sequence in 1...max(1, pastCount + 1) {
            context.insert(HistoryEntry(sequence: sequence, projectedAt: start.addingTimeInterval(TimeInterval(sequence)), card: nil, deck: deck))
        }
        deck.highestReachedSequence = pastCount == 0 ? nil : pastCount + 1
        try context.save()
        return (container, deck.persistentModelID, start)
    }

    @Test(arguments: [0, 1, 20, 21, 420])
    func boundedPagesAndStableSession(pastCount: Int) throws {
        let (container, deckID, _) = try fixture(pastCount: pastCount)
        var snapshot = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(snapshot.past.count == min(20, pastCount))
        #expect(snapshot.past.map(\.sequence) == Array((1...max(1, pastCount)).reversed().prefix(min(20, pastCount))))
        #expect(snapshot.hasMorePast == (pastCount > 20))
        let firstPage = snapshot.past
        if pastCount > 20 {
            try snapshot.loadMorePast(deckID: deckID, from: container)
            #expect(snapshot.past.count == min(40, pastCount))
            #expect(Array(snapshot.past.prefix(20)) == firstPage)
            #expect(Set(snapshot.past.map(\.sequence)).count == snapshot.past.count)
        }
        let writer = ModelContext(container)
        let deck = try #require(writer.model(for: deckID) as? Deck)
        deck.highestReachedSequence = (deck.highestReachedSequence ?? 0) + 1
        try writer.save()
        #expect(snapshot.past.prefix(firstPage.count).map(\.sequence) == firstPage.map(\.sequence))
        #expect(snapshot.watermark == (pastCount == 0 ? nil : pastCount + 1))
    }
}
