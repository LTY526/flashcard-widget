//
//  DeckScheduler.swift
//  flashcard-widget
//
//  Owns every rule from ADR 0002 decisions 4 and 5: per-deck queue
//  top-up, Next/Back, the two reset triggers (order change, soft-delete
//  reconciliation), and history pagination. All entry points are no-ops
//  (not crashes) on a deck with zero active cards, and every
//  regeneration path is gated by `Deck.isPaused` -- except the *discard*
//  half of a reset, which always runs.
//
//  `sequence` is the only thing "next"/"previous" is ever defined in
//  terms of; `projectedAt` is purely informational.
//

import Foundation
import SwiftData

enum DeckScheduler {
    /// A non-paused deck with at least one active card always has at
    /// least this many `HistoryEntry` rows queued (generated but not yet
    /// reached).
    static let queueSize = 10

    // MARK: - Reading a deck's schedule

    /// Call whenever a deck's schedule is read (Deck Detail, the deck
    /// list, right after import, right after unpausing, as part of a
    /// Next/Back tap). Tops the unreached queue back up to `queueSize` if
    /// the deck isn't paused and has at least one active card; otherwise a
    /// no-op.
    static func readSchedule(for deck: Deck, in modelContext: ModelContext) {
        topUp(deck, in: modelContext)
    }

    // MARK: - Next / Back

    /// Complete no-op while `deck.isPaused` -- no entry is consumed, no
    /// `projectedAt` changes, and the pointer/`highestReachedSequence` are
    /// untouched. This check happens before anything else. Also a no-op
    /// (not a crash) when the deck has zero active cards.
    static func next(_ deck: Deck, in modelContext: ModelContext) {
        guard !deck.isPaused else { return }
        guard !deck.activeCards.isEmpty else { return }

        // Tops up one more first if the target doesn't already exist yet
        // (should only happen if top-up has fallen behind).
        topUp(deck, in: modelContext)

        let targetSequence = (deck.highestReachedSequence ?? 0) + 1
        guard let targetEntry = deck.historyEntries.first(where: { $0.sequence == targetSequence }) else {
            return
        }

        let intervalMinutes = deck.displayConfig?.intervalMinutes ?? DisplayConfig.defaultIntervalMinutes
        let intervalSeconds = TimeInterval(intervalMinutes) * 60
        let now = Date()

        targetEntry.projectedAt = now

        let laterEntries = deck.historyEntries
            .filter { $0.sequence > targetSequence }
            .sorted { $0.sequence < $1.sequence }
        var anchor = now
        for entry in laterEntries {
            anchor = anchor.addingTimeInterval(intervalSeconds)
            entry.projectedAt = anchor
        }

        deck.activeHistoryEntry = targetEntry
        deck.highestReachedSequence = targetSequence

        topUp(deck, in: modelContext)
    }

    /// Moves the pointer to the entry with the next-lower `sequence`.
    /// Changes nothing else -- no new/deleted rows, no `projectedAt` or
    /// `highestReachedSequence` change. No-op when the pointer is `nil` or
    /// already at the lowest-`sequence` entry that still exists.
    static func back(_ deck: Deck) {
        guard let current = deck.activeHistoryEntry else { return }
        let previous = deck.historyEntries
            .filter { $0.sequence < current.sequence }
            .max { $0.sequence < $1.sequence }
        guard let previous else { return }
        deck.activeHistoryEntry = previous
    }

    /// Whether `back(_:)` would currently do anything.
    static func canGoBack(_ deck: Deck) -> Bool {
        guard let current = deck.activeHistoryEntry else { return false }
        return deck.historyEntries.contains { $0.sequence < current.sequence }
    }

    // MARK: - Reset primitive (order change / soft-delete reconciliation)

    /// Config `order` change: discards the unreached queue (always), then
    /// regenerates it per the new `order` if the deck isn't paused.
    static func handleOrderChange(for deck: Deck, in modelContext: ModelContext) {
        discardUnreachedQueue(deck, in: modelContext)
        topUp(deck, in: modelContext)
    }

    /// Re-import soft-delete reconciliation for a deck that had one or
    /// more cards soft-deleted this import: discards the unreached queue
    /// (always, regardless of pause), clears the pointer if its own
    /// entry's card was among those soft-deleted (without deleting that
    /// row), then regenerates if the deck isn't paused.
    static func handleSoftDelete(for deck: Deck, in modelContext: ModelContext) {
        discardUnreachedQueue(deck, in: modelContext)
        if let current = deck.activeHistoryEntry, let card = current.card, !card.isActive {
            deck.activeHistoryEntry = nil
        }
        topUp(deck, in: modelContext)
    }

    /// Deletes every `HistoryEntry` with `sequence > highestReachedSequence`
    /// for this deck (the unreached queue only -- the current entry and
    /// all real history are untouched). Always runs, paused or not.
    ///
    /// Also explicitly prunes `deck.historyEntries` in memory: `modelContext.
    /// delete(_:)` doesn't synchronously remove the deleted object from
    /// other objects' already-materialized relationship arrays within the
    /// same context, so leaving that to happen implicitly would let a
    /// zombie entry keep being counted as "still queued" by every later
    /// step in this same call (e.g. `topUp` deciding it already has 10 and
    /// declining to regenerate).
    ///
    /// Rewinds `nextHistorySequence` back down to `highestReachedSequence +
    /// 1`: every discarded row's `sequence` was strictly greater than that,
    /// so those numbers are now unused by any surviving row anywhere (they
    /// were never reached, so they never became real history) and are free
    /// to be reissued. Without this, regeneration would keep counting up
    /// from wherever the discarded rows left off, leaving a permanent gap
    /// between `highestReachedSequence` and the next real row -- which
    /// breaks "Next" (decision 4), whose `sequence == highestReachedSequence
    /// + 1` lookup depends on that contiguity.
    private static func discardUnreachedQueue(_ deck: Deck, in modelContext: ModelContext) {
        let toDiscard = unreachedEntries(for: deck)
        guard !toDiscard.isEmpty else { return }
        let discardedIDs = Set(toDiscard.map(\.persistentModelID))
        for entry in toDiscard {
            modelContext.delete(entry)
        }
        deck.historyEntries.removeAll { discardedIDs.contains($0.persistentModelID) }
        deck.nextHistorySequence = (deck.highestReachedSequence ?? 0) + 1
    }

    // MARK: - History pagination

    /// `HistoryEntry` rows with `sequence <= highestReachedSequence`
    /// (never entries still sitting unreached in the queue), sorted by
    /// `sequence` descending.
    static func reachedEntries(for deck: Deck) -> [HistoryEntry] {
        guard let highest = deck.highestReachedSequence else { return [] }
        return deck.historyEntries
            .filter { $0.sequence <= highest }
            .sorted { $0.sequence > $1.sequence }
    }

    /// Loads `limit` reached entries at a time, starting at `offset` into
    /// the descending-by-`sequence` reached list. Never includes an
    /// unreached queue entry.
    static func historyPage(for deck: Deck, offset: Int, limit: Int = queueSize) -> [HistoryEntry] {
        let all = reachedEntries(for: deck)
        guard offset < all.count else { return [] }
        return Array(all[offset..<min(offset + limit, all.count)])
    }

    // MARK: - Top-up

    /// Ensures at least `queueSize` unreached rows exist. No-op if the
    /// deck is paused, or if it has zero active cards (nothing to
    /// generate -- the deck simply stays below `queueSize`, possibly at 0,
    /// until it has an active card again).
    private static func topUp(_ deck: Deck, in modelContext: ModelContext) {
        guard !deck.isPaused else { return }
        guard !deck.activeCards.isEmpty else { return }
        while unreachedEntries(for: deck).count < queueSize {
            guard let entry = generateNextEntry(for: deck) else { break }
            modelContext.insert(entry)
        }
    }

    /// All currently-unreached entries for a deck (`sequence >
    /// highestReachedSequence`, or every entry if `highestReachedSequence`
    /// is `nil`), sorted ascending by `sequence`.
    private static func unreachedEntries(for deck: Deck) -> [HistoryEntry] {
        let highest = deck.highestReachedSequence ?? 0
        return deck.historyEntries
            .filter { $0.sequence > highest }
            .sorted { $0.sequence < $1.sequence }
    }

    /// Generates exactly one new queued entry, chained off "the reference
    /// entry" (ADR 0002, decision 4):
    /// 1. the highest-`sequence` entry among the *actual current* unreached
    ///    queue, regardless of when it was generated;
    /// 2. else the pointer's own entry, if the pointer is non-`nil`;
    /// 3. else (no unreached entry *and* the pointer is `nil`) there's no
    ///    reference entry -- the empty-queue rule applies. This check is
    ///    always on the pointer, never on `highestReachedSequence`.
    private static func generateNextEntry(for deck: Deck) -> HistoryEntry? {
        let activeCards = deck.activeCards
        guard !activeCards.isEmpty else { return nil }

        let order = deck.displayConfig?.order ?? .sequential
        let intervalMinutes = deck.displayConfig?.intervalMinutes ?? DisplayConfig.defaultIntervalMinutes

        if let reference = unreachedEntries(for: deck).last {
            return chainedEntry(after: reference, order: order, intervalMinutes: intervalMinutes, activeCards: activeCards, deck: deck)
        }
        if let pointerEntry = deck.activeHistoryEntry {
            return chainedEntry(after: pointerEntry, order: order, intervalMinutes: intervalMinutes, activeCards: activeCards, deck: deck)
        }

        // Empty-queue rule: never had a Next, or pointer just cleared and
        // queue fully discarded.
        let card: Card
        switch order {
        case .sequential:
            card = activeCards.min { $0.ankiCardID < $1.ankiCardID }!
        case .random:
            card = activeCards.randomElement()!
        }
        let sequence = deck.consumeNextSequence()
        let projectedAt = Date().addingTimeInterval(TimeInterval(intervalMinutes) * 60)
        return HistoryEntry(sequence: sequence, projectedAt: projectedAt, card: card, deck: deck)
    }

    private static func chainedEntry(
        after reference: HistoryEntry,
        order: DisplayOrder,
        intervalMinutes: Int,
        activeCards: [Card],
        deck: Deck
    ) -> HistoryEntry {
        let card: Card
        switch order {
        case .sequential:
            card = nextSequentialCard(after: reference.card, activeCards: activeCards)
        case .random:
            card = randomCard(excluding: reference.card, activeCards: activeCards)
        }
        let sequence = deck.consumeNextSequence()
        let projectedAt = reference.projectedAt.addingTimeInterval(TimeInterval(intervalMinutes) * 60)
        return HistoryEntry(sequence: sequence, projectedAt: projectedAt, card: card, deck: deck)
    }

    /// Next active card after `card` by `ankiCardID`, wrapping to the
    /// first after the last. Falls back to the lowest-`ankiCardID` active
    /// card if `card` is `nil` or no longer found among active cards.
    private static func nextSequentialCard(after card: Card?, activeCards: [Card]) -> Card {
        let sorted = activeCards.sorted { $0.ankiCardID < $1.ankiCardID }
        guard let card, let index = sorted.firstIndex(where: { $0.persistentModelID == card.persistentModelID }) else {
            return sorted[0]
        }
        return sorted[(index + 1) % sorted.count]
    }

    /// A random active card other than `card`, whenever more than one
    /// active card exists; otherwise (or if `card` is `nil`) any active
    /// card.
    private static func randomCard(excluding card: Card?, activeCards: [Card]) -> Card {
        if let card, activeCards.count > 1 {
            let others = activeCards.filter { $0.persistentModelID != card.persistentModelID }
            if let picked = others.randomElement() {
                return picked
            }
        }
        return activeCards.randomElement()!
    }
}
