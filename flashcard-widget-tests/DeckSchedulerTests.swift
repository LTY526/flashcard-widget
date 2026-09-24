//
//  DeckSchedulerTests.swift
//  flashcard-widget-tests
//
//  Acceptance tests for docs/specs/active-card-deck-management.md and
//  ADR 0002 -- per-deck scheduled queue, active card, Next/Back,
//  pause/resume, DisplayConfig, and history pagination.
//

import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([Deck.self, NoteType.self, NoteTypeField.self, Note.self, Card.self, MediaItem.self, DisplayConfig.self, HistoryEntry.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}

@MainActor
private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
    try context.fetch(FetchDescriptor<T>())
}

@MainActor
private func makeDeck(
    ankiID: Int64,
    name: String = "Deck",
    order: DisplayOrder = .sequential,
    intervalMinutes: Int = 30,
    in context: ModelContext
) -> Deck {
    let deck = Deck(ankiDeckID: ankiID, name: name)
    context.insert(deck)
    let config = DisplayConfig(order: order, intervalMinutes: intervalMinutes)
    config.deck = deck
    deck.displayConfig = config
    context.insert(config)
    return deck
}

/// A card with its own backing note (so `note`/`card` relationships are
/// always populated, matching real imported data).
@MainActor
private func makeCard(ankiID: Int64, deck: Deck, in context: ModelContext) -> Card {
    let note = Note(ankiNoteID: ankiID, fieldValues: ["front \(ankiID)"], noteType: nil)
    context.insert(note)
    let card = Card(ankiCardID: ankiID, ordinal: 0, note: note, deck: deck)
    context.insert(card)
    return card
}

@MainActor
@Suite("deck scheduler")
struct DeckSchedulerTests {

    // MARK: - Top-up / reference-entry rule

    @Test("steady-state top-up chains off the pre-existing unreached queue, not the just-consumed pointer entry")
    func topUpChainsOffPreExistingQueueNotStalePointer() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, intervalMinutes: 15, in: context)
        for id in [1, 2, 3, 4] as [Int64] { _ = makeCard(ankiID: id, deck: deck, in: context) }
        try context.save()

        DeckScheduler.ensureSchedule(for: deck, in: context)
        let seeded = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        #expect(seeded.count == DeckScheduler.queueSize + 1)
        // Deterministic empty-queue-rule pattern for 4 active cards [1,2,3,4]:
        #expect(Array(seeded.prefix(11)).map { $0.card?.ankiCardID } == [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3])
        let preExistingProjectedAts = Set(seeded.filter { $0.sequence > 1 }.map(\.projectedAt))

        DeckScheduler.next(deck, in: context) // consumes sequence 1 (card 1)

        let after = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        // Sequence 1 is reconciled because it is due at seed time, then Next
        // advances sequence 2. The configured number of rows remain unreached.
        #expect(after.count == DeckScheduler.queueSize + 2)
        let unreachedAfter = after.filter { $0.sequence > 2 }
        #expect(unreachedAfter.count == DeckScheduler.queueSize)
        let generatedSequence = DeckScheduler.queueSize + 2
        let generated = try #require(after.first { $0.sequence == generatedSequence })

        // The highest-sequence entry still unreached before this call was
        // the previous queue tail -- chaining must continue from that card.
        // Chaining off the just-consumed pointer entry (sequence 1, card 1)
        // would wrongly produce card 2 instead. Asserting the exact value
        // (not just "differs from repeat") pins down which rule actually
        // ran.
        #expect(generated.card?.ankiCardID == 2)
        #expect(!preExistingProjectedAts.contains(generated.projectedAt), "must not collide with any pre-existing queued entry's projectedAt")

        let priorTail = try #require(after.first { $0.sequence == DeckScheduler.queueSize + 1 })
        let expectedProjectedAt = priorTail.projectedAt.addingTimeInterval(15 * 60)
        #expect(abs(generated.projectedAt.timeIntervalSince(expectedProjectedAt)) < 0.001)
    }

    @Test(".sequential order visits every active card exactly once before repeating, in ankiCardID order")
    func sequentialOrderVisitsEveryCardOnceInOrder() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, in: context)
        // Intentionally inserted out of ankiCardID order.
        for id in [30, 10, 20] as [Int64] { _ = makeCard(ankiID: id, deck: deck, in: context) }
        try context.save()

        var visited: [Int64] = []
        for _ in 0..<6 { // two full laps
            DeckScheduler.next(deck, in: context)
            if let ankiID = deck.activeHistoryEntry?.card?.ankiCardID {
                visited.append(ankiID)
            }
        }
        #expect(visited == [10, 20, 30, 10, 20, 30])
    }

    @Test(".random order never repeats the immediately-previous card twice in a row")
    func randomOrderNeverImmediatelyRepeats() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .random, in: context)
        _ = makeCard(ankiID: 1, deck: deck, in: context)
        _ = makeCard(ankiID: 2, deck: deck, in: context)
        try context.save()

        var consumedCardIDs: [PersistentIdentifier] = []
        for _ in 0..<60 {
            DeckScheduler.next(deck, in: context)
            if let cardID = deck.activeHistoryEntry?.card?.persistentModelID {
                consumedCardIDs.append(cardID)
            }
        }
        #expect(consumedCardIDs.count == 60)
        for i in 1..<consumedCardIDs.count {
            #expect(consumedCardIDs[i] != consumedCardIDs[i - 1], "random order must never repeat the immediately-previous card")
        }
        #expect(Set(consumedCardIDs).count == 2, "both cards must actually get picked across 60 trials")
    }

    // MARK: - Next

    @Test("driving Next repeatedly advances highestReachedSequence contiguously and cascades later projectedAt values")
    func nextAdvancesContiguouslyAndCascades() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, intervalMinutes: 20, in: context)
        for id in [1, 2, 3] as [Int64] { _ = makeCard(ankiID: id, deck: deck, in: context) }
        try context.save()

        DeckScheduler.ensureSchedule(for: deck, in: context)
        #expect(deck.historyEntries.count == DeckScheduler.queueSize + 1)

        var previousHighest: Int?
        for _ in 0..<5 {
            DeckScheduler.next(deck, in: context)
            let newHighest = try #require(deck.highestReachedSequence)
            if let previousHighest {
                #expect(newHighest == previousHighest + 1, "sequence values consumed must be contiguous")
            } else {
                #expect(newHighest == 2)
            }
            previousHighest = newHighest

            let current = try #require(deck.activeHistoryEntry)
            let unreached = deck.historyEntries.filter { $0.sequence > newHighest }.sorted { $0.sequence < $1.sequence }
            var anchor = current.projectedAt
            for entry in unreached {
                let expected = anchor.addingTimeInterval(20 * 60)
                #expect(abs(entry.projectedAt.timeIntervalSince(expected)) < 0.001, "each later queued entry must stay intervalMinutes apart from the new anchor")
                anchor = entry.projectedAt
            }
        }
    }

    @Test("Next on a deck with zero active cards is a no-op, not a crash")
    func nextWithZeroActiveCardsIsNoOp() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, in: context)
        try context.save()

        DeckScheduler.next(deck, in: context)

        #expect(deck.historyEntries.isEmpty)
        #expect(deck.activeHistoryEntry == nil)
        #expect(deck.highestReachedSequence == nil)
    }

    @Test("Next on a paused deck is a complete no-op")
    func nextOnPausedDeckIsNoOp() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, in: context)
        _ = makeCard(ankiID: 1, deck: deck, in: context)
        try context.save()
        DeckScheduler.ensureSchedule(for: deck, in: context)
        let beforeSorted = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        let beforeIDs: [PersistentIdentifier] = beforeSorted.map(\.persistentModelID)
        let beforeDates: [Date] = beforeSorted.map(\.projectedAt)

        deck.isPaused = true
        DeckScheduler.next(deck, in: context)

        #expect(deck.activeHistoryEntry?.sequence == 1)
        #expect(deck.highestReachedSequence == 1)
        let afterSorted = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        let afterIDs: [PersistentIdentifier] = afterSorted.map(\.persistentModelID)
        let afterDates: [Date] = afterSorted.map(\.projectedAt)
        #expect(afterIDs == beforeIDs)
        #expect(afterDates == beforeDates)
    }

    // MARK: - Reset primitive: order change

    @Test("changing order discards and regenerates the full unreached queue, leaving current and history untouched")
    func orderChangeDiscardsAndRegenerates() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, in: context)
        for id in [1, 2, 3] as [Int64] { _ = makeCard(ankiID: id, deck: deck, in: context) }
        try context.save()

        DeckScheduler.next(deck, in: context)
        let currentEntry = try #require(deck.activeHistoryEntry)
        let unreachedIDsBefore = Set(deck.historyEntries.filter { $0.sequence > (deck.highestReachedSequence ?? 0) }.map(\.persistentModelID))
        #expect(unreachedIDsBefore.count == DeckScheduler.queueSize)

        deck.displayConfig?.order = .random
        DeckScheduler.handleOrderChange(for: deck, in: context)

        let afterChange = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        let unreachedAfter = afterChange.filter { $0.sequence > (deck.highestReachedSequence ?? 0) }
        #expect(unreachedAfter.count == DeckScheduler.queueSize)
        #expect(Set(unreachedAfter.map(\.persistentModelID)).isDisjoint(with: unreachedIDsBefore), "every entry queued before the change is gone")

        #expect(deck.activeHistoryEntry?.persistentModelID == currentEntry.persistentModelID)
        let reachedAfter = afterChange.filter { $0.sequence <= (deck.highestReachedSequence ?? 0) }
        #expect(reachedAfter.map(\.persistentModelID) == [currentEntry.persistentModelID])
    }

    // MARK: - Reset primitive: soft-delete reconciliation

    @Test("soft-deleting a card referenced only by an unreached queued entry discards the whole queue but leaves the pointer untouched")
    func softDeleteOfUnreachedOnlyCardDiscardsQueueLeavesPointer() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, in: context)
        let cardA = makeCard(ankiID: 1, deck: deck, in: context)
        let cardB = makeCard(ankiID: 2, deck: deck, in: context)
        try context.save()

        DeckScheduler.next(deck, in: context) // pointer -> sequence 1 (lowest ankiCardID: cardA)
        let currentEntry = try #require(deck.activeHistoryEntry)
        #expect(currentEntry.card?.persistentModelID == cardA.persistentModelID)

        let unreachedBefore = deck.historyEntries.filter { $0.sequence > (deck.highestReachedSequence ?? 0) }
        #expect(unreachedBefore.count == DeckScheduler.queueSize)
        let unreachedIDsBefore = Set(unreachedBefore.map(\.persistentModelID))
        #expect(unreachedBefore.contains { $0.card?.persistentModelID == cardB.persistentModelID }, "cardB must appear in the unreached queue for this test to be meaningful")

        cardB.removedAt = Date() // soft-deleted; referenced only by an unreached entry
        DeckScheduler.handleSoftDelete(for: deck, in: context)

        #expect(deck.activeHistoryEntry?.persistentModelID == currentEntry.persistentModelID, "pointer unaffected")

        let unreachedAfter = deck.historyEntries.filter { $0.sequence > (deck.highestReachedSequence ?? 0) }
        #expect(unreachedAfter.count == DeckScheduler.queueSize, "the full queue is freshly generated afterward")
        #expect(Set(unreachedAfter.map(\.persistentModelID)).isDisjoint(with: unreachedIDsBefore), "every entry that was in the unreached queue before -- including the contaminated one -- is gone")
    }

    // MARK: - Pause / resume

    @Test("pausing freezes the queue; unpausing restores the configured queue size")
    func pauseFreezesQueueUnpauseResumes() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, in: context)
        for id in [1, 2, 3] as [Int64] { _ = makeCard(ankiID: id, deck: deck, in: context) }
        try context.save()

        DeckScheduler.ensureSchedule(for: deck, in: context)
        #expect(deck.historyEntries.count == DeckScheduler.queueSize + 1)

        deck.isPaused = true

        // Simulate a discard that ran while paused, leaving a short queue.
        // (Mirrors DeckScheduler's own discard: deleting from the context
        // alone doesn't synchronously drop the entry from `deck.
        // historyEntries`, so the array is pruned explicitly too.)
        let toDrop = deck.historyEntries.sorted { $0.sequence < $1.sequence }.suffix(3)
        let droppedIDs = Set(toDrop.map(\.persistentModelID))
        for entry in toDrop { context.delete(entry) }
        deck.historyEntries.removeAll { droppedIDs.contains($0.persistentModelID) }
        let shortCount = deck.historyEntries.count
        #expect(shortCount == DeckScheduler.queueSize - 2)
        let snapshotSorted = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        let snapshotIDs: [PersistentIdentifier] = snapshotSorted.map(\.persistentModelID)
        let snapshotDates: [Date] = snapshotSorted.map(\.projectedAt)

        DeckScheduler.ensureSchedule(for: deck, in: context) // would-be top-up: must no-op
        DeckScheduler.next(deck, in: context) // would-be Next: must no-op

        let afterPaused = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        #expect(afterPaused.count == shortCount)
        let afterPausedIDs: [PersistentIdentifier] = afterPaused.map(\.persistentModelID)
        let afterPausedDates: [Date] = afterPaused.map(\.projectedAt)
        #expect(afterPausedIDs == snapshotIDs)
        #expect(afterPausedDates == snapshotDates)
        #expect(deck.activeHistoryEntry?.sequence == 1)
        #expect(deck.highestReachedSequence == 1)

        deck.isPaused = false
        DeckScheduler.ensureSchedule(for: deck, in: context)
        #expect(deck.historyEntries.count == DeckScheduler.queueSize + 1)
    }

    @Test("changing order on a paused deck discards the unreached queue but doesn't regenerate until unpaused")
    func orderChangeWhilePausedDiscardsNotRegenerates() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, in: context)
        for id in [1, 2, 3] as [Int64] { _ = makeCard(ankiID: id, deck: deck, in: context) }
        try context.save()
        DeckScheduler.ensureSchedule(for: deck, in: context)
        #expect(deck.historyEntries.count == DeckScheduler.queueSize + 1)

        deck.isPaused = true
        deck.displayConfig?.order = .random
        DeckScheduler.handleOrderChange(for: deck, in: context)

        #expect(deck.historyEntries.count == 1, "only the current row remains while paused")

        deck.isPaused = false
        DeckScheduler.ensureSchedule(for: deck, in: context)
        #expect(deck.historyEntries.count == DeckScheduler.queueSize + 1, "keeps current plus the full future queue once unpaused")
    }

    @Test("re-importing a fixture that soft-deletes a paused deck's current card discards the queue but defers regeneration until unpaused")
    func softDeleteWhilePausedDiscardsNotRegenerates() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck"), modelContext: context)
        let deck = try #require(try fetchAll(Deck.self, in: context).first)
        #expect(deck.historyEntries.count == DeckScheduler.queueSize + 1, "seeded with current plus future queue on import")

        deck.isPaused = true
        try context.save()

        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck_removed"), modelContext: context)

        #expect(deck.historyEntries.count == 1, "reached history remains even though the deck is paused")

        deck.isPaused = false
        DeckScheduler.ensureSchedule(for: deck, in: context)
        #expect(deck.historyEntries.count == DeckScheduler.queueSize + 1, "keeps current plus the full future queue once unpaused")
    }

    @Test("pause with history -> soft-delete clears the pointer -> unpause -> read regenerates via the empty-queue rule even though highestReachedSequence is non-nil")
    func pauseSoftDeleteUnpauseRegeneratesViaEmptyQueueRule() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, intervalMinutes: 30, in: context)
        let cardA = makeCard(ankiID: 10, deck: deck, in: context) // lowest ankiCardID
        let cardB = makeCard(ankiID: 20, deck: deck, in: context)
        try context.save()

        DeckScheduler.next(deck, in: context) // consumes sequence 1 -> empty-queue rule picks lowest ankiCardID: cardA
        #expect(deck.activeHistoryEntry?.card?.persistentModelID == cardA.persistentModelID)
        #expect(deck.highestReachedSequence == 1)

        deck.isPaused = true

        // Simulate a re-import's reconciliation soft-deleting the pointer's
        // own card while the deck is paused.
        cardA.removedAt = Date()
        DeckScheduler.handleSoftDelete(for: deck, in: context)

        #expect(deck.activeHistoryEntry == nil, "pointer cleared since its card was soft-deleted")
        #expect(deck.highestReachedSequence == 1, "highestReachedSequence must remain at its old, non-nil value")
        let unreachedWhilePaused = deck.historyEntries.filter { $0.sequence > (deck.highestReachedSequence ?? 0) }
        #expect(unreachedWhilePaused.isEmpty, "regeneration deferred while paused")

        deck.isPaused = false
        DeckScheduler.ensureSchedule(for: deck, in: context)

        let unreachedAfter = deck.historyEntries
            .filter { $0.sequence > (deck.highestReachedSequence ?? 0) }
            .sorted { $0.sequence < $1.sequence }
        #expect(unreachedAfter.count == DeckScheduler.queueSize, "the highestReachedSequence-is-non-nil-but-pointer-is-nil case must still use the empty-queue rule, not get stuck")
        // Only cardB remains active; the empty-queue rule for .sequential
        // must chain onto it (the lowest-ankiCardID -- and only -- active
        // card).
        #expect(unreachedAfter.allSatisfy { $0.card?.persistentModelID == cardB.persistentModelID })
    }

    // MARK: - History pagination

    // MARK: - DisplayConfig

    @Test("editing a deck's DisplayConfig fields persists the change")
    func editingConfigPersists() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, in: context)
        try context.save()

        let config = try #require(deck.displayConfig)
        config.order = .random
        config.updateIntervalMinutes(45)
        try context.save()

        let deckID = deck.persistentModelID
        let reloaded = try #require(context.model(for: deckID) as? Deck)
        #expect(reloaded.displayConfig?.order == .random)
        #expect(reloaded.displayConfig?.intervalMinutes == 45)
    }

    @Test("editing intervalMinutes only affects entries generated after the edit, not already-queued ones")
    func editingIntervalOnlyAffectsFutureEntries() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, order: .sequential, intervalMinutes: 30, in: context)
        for id in [1, 2] as [Int64] { _ = makeCard(ankiID: id, deck: deck, in: context) }
        try context.save()

        DeckScheduler.ensureSchedule(for: deck, in: context)
        let beforeEdit = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        #expect(beforeEdit.count == DeckScheduler.queueSize + 1)
        let projectedAtsBefore = Dictionary(uniqueKeysWithValues: beforeEdit.map { ($0.persistentModelID, $0.projectedAt) })

        deck.displayConfig?.updateIntervalMinutes(60)

        let afterEdit = deck.historyEntries.sorted { $0.sequence < $1.sequence }
        for entry in afterEdit {
            #expect(entry.projectedAt == projectedAtsBefore[entry.persistentModelID], "editing intervalMinutes must not retroactively rewrite already-queued entries")
        }

        DeckScheduler.next(deck, in: context)
        let generated = try #require(deck.historyEntries.first { $0.sequence == DeckScheduler.queueSize + 2 })
        let referenceEntry = try #require(deck.historyEntries.first { $0.sequence == DeckScheduler.queueSize + 1 })
        let expected = referenceEntry.projectedAt.addingTimeInterval(60 * 60)
        #expect(abs(generated.projectedAt.timeIntervalSince(expected)) < 0.001, "the next top-up-generated entry must use the new spacing")
    }

    @Test("intervalMinutes below the 15-minute floor is clamped, both at init and on later edits")
    func intervalMinutesFloorIsEnforced() throws {
        #expect(DisplayConfig.clampedIntervalMinutes(5) == 15)
        #expect(DisplayConfig.clampedIntervalMinutes(15) == 15)
        #expect(DisplayConfig.clampedIntervalMinutes(20) == 20)

        let config = DisplayConfig(intervalMinutes: 5)
        #expect(config.intervalMinutes == 15)

        config.updateIntervalMinutes(1)
        #expect(config.intervalMinutes == 15)
    }
}
