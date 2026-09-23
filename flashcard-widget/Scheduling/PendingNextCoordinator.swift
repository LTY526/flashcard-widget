import Foundation
import Observation
import SwiftData

enum PendingRebuildError: Error { case deckUnavailable }

/// Lives at the root so a navigation pop cannot discard a pending Next rebuild.
@MainActor @Observable
final class PendingNextCoordinator {
    private var pending: [Int64: Date] = [:]
    private var failedDeckIDs: Set<Int64> = []
    @ObservationIgnored private var timers: [Int64: Task<Void, Never>] = [:]
    @ObservationIgnored private var rebuild: (Int64, Date) throws -> Void
    @ObservationIgnored private var reload: () -> Void
    private(set) var errorMessage: String?

    init(
        rebuild: @escaping (Int64, Date) throws -> Void = { _, _ in },
        reload: @escaping () -> Void = {}
    ) {
        self.rebuild = rebuild
        self.reload = reload
    }

    func configure(context: ModelContext) {
        rebuild = { id, anchor in
            try ScheduleFileLock.shared().withExclusiveLock {
                do {
                    var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.ankiDeckID == id })
                    descriptor.fetchLimit = 1
                    guard let deck = try context.fetch(descriptor).first else {
                        throw PendingRebuildError.deckUnavailable
                    }
                    try DeckScheduler.rebuildFuture(for: deck, in: context, now: anchor)
                    try context.save()
                } catch {
                    context.rollback()
                    throw error
                }
            }
        }
        reload = { Task { await WidgetTimelineReloader.shared.scheduleReload() } }
    }

    func hasPending(deckID: Int64) -> Bool { pending[deckID] != nil }
    var hasPendingWork: Bool { !pending.isEmpty }

    func cancelAfterDeletion(deckID: Int64) {
        timers[deckID]?.cancel()
        timers[deckID] = nil
        pending[deckID] = nil
        failedDeckIDs.remove(deckID)
        if pending.isEmpty { errorMessage = nil }
    }

    func schedule(deckID: Int64, after anchor: Date) {
        timers[deckID]?.cancel()
        pending[deckID] = anchor
        timers[deckID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.expireTimer(deckID: deckID)
        }
    }

    func expireTimer(deckID: Int64) {
        do { try flush(deckIDs: [deckID]) }
        catch { /* retry remains visible */ }
    }

    func flush(deckIDs: Set<Int64>) throws {
        for id in deckIDs.sorted() {
            guard let anchor = pending[id] else { continue }
            timers[id]?.cancel()
            timers[id] = nil
            do {
                try rebuild(id, anchor)
                pending[id] = nil
                failedDeckIDs.remove(id)
                reload()
            } catch {
                failedDeckIDs.insert(id)
                errorMessage = "Couldn't finish updating the schedule. Please retry."
                throw error
            }
        }
        if pending.isEmpty { errorMessage = nil }
    }

    func retry() throws { try flush(deckIDs: Set(pending.keys)) }

    func performMutation(affectedDeckIDs: Set<Int64>, _ operation: () throws -> Void) throws {
        try flush(deckIDs: affectedDeckIDs)
        try operation()
    }

    /// Rapid Next taps coalesce, but a failed rebuild must succeed before
    /// another pointer advance for that deck.
    func performNextMutation(deckID: Int64, _ operation: () throws -> Void) throws {
        if failedDeckIDs.contains(deckID) { try flush(deckIDs: [deckID]) }
        try operation()
    }
}
