import Foundation
import Testing
@testable import flashcard_widget

@MainActor
struct TabbedDeckDetailAcceptanceTests {
    private enum Failure: Error { case lock, save }

    @Test("opening and deep linking select Current without duplicating a route")
    func detailRouting() {
        var route = DeckDetailRoute()
        #expect(route.mode == .current)
        route.open(42)
        route.select(.config)
        route.openDeepLink(42)
        #expect(route.path == [42])
        #expect(route.mode == .current)
        route.openDeepLink(nil)
        #expect(route.path.isEmpty)
    }

    @Test("cold widget link is retained until saved decks have been queried")
    func deferredColdLink() {
        var route = DeckDetailRoute()
        route.requestDeepLink(42)
        #expect(route.path.isEmpty)
        #expect(route.requestedDeepLinkID == 42)
        route.resolveRequestedDeepLink(exists: true)
        #expect(route.path == [42])
        route.select(.schedule)
        route.requestDeepLink(42)
        route.resolveRequestedDeepLink(exists: true)
        #expect(route.path == [42])
        #expect(route.mode == .current)
        route.requestDeepLink(100)
        route.resolveRequestedDeepLink(exists: false)
        #expect(route.path.isEmpty)
    }

    @Test("Schedule subsection survives a fresh snapshot and another mode")
    func scheduleSelection() {
        var route = DeckDetailRoute()
        route.open(42)
        route.select(.schedule)
        route.scheduleTab = .past
        route.select(.current)
        route.select(.schedule)
        #expect(route.scheduleTab == .past)
    }

    @Test("pending Next survives lock and save failures and commits exactly once")
    func retryPendingRebuild() throws {
        var attempts = 0
        var saves = 0
        var reloads = 0
        let anchor = Date(timeIntervalSince1970: 100)
        let coordinator = PendingNextCoordinator(rebuild: { id, date in
            #expect(id == 42)
            #expect(date == anchor)
            attempts += 1
            if attempts == 1 { throw Failure.lock }
            if attempts == 2 { throw Failure.save }
            saves += 1
        }, reload: { reloads += 1 })
        coordinator.schedule(deckID: 42, after: anchor)
        #expect(throws: Failure.self) { try coordinator.flush(deckIDs: [42]) }
        #expect(coordinator.hasPending(deckID: 42))
        #expect(throws: Failure.self) { try coordinator.performMutation(affectedDeckIDs: [42]) { saves += 100 } }
        #expect(saves == 0)
        try coordinator.retry()
        #expect(!coordinator.hasPending(deckID: 42))
        #expect(saves == 1)
        #expect(reloads == 1)
        try coordinator.flush(deckIDs: [42])
        coordinator.expireTimer(deckID: 42)
        #expect(attempts == 3)
    }

    @Test("shared mapping gates every affected deck and preserves other pending work")
    func sharedMutation() throws {
        var rebuilt: [Int64] = []
        let coordinator = PendingNextCoordinator(rebuild: { id, _ in
            if id == 1 { throw Failure.lock }
            rebuilt.append(id)
        }, reload: {})
        coordinator.schedule(deckID: 1, after: .now)
        coordinator.schedule(deckID: 2, after: .now)
        var mutated = false
        #expect(throws: Failure.self) {
            try coordinator.performMutation(affectedDeckIDs: [1, 2]) { mutated = true }
        }
        #expect(!mutated)
        #expect(coordinator.hasPending(deckID: 1))
    }

    @Test("rapid Next taps retain the latest anchor for one debounced rebuild")
    func rapidNextCoalesces() throws {
        var rebuilds: [Date] = []
        let coordinator = PendingNextCoordinator(rebuild: { _, anchor in
            rebuilds.append(anchor)
        }, reload: {})
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 101)
        var advances = 0
        try coordinator.performNextMutation(deckID: 42) { advances += 1 }
        coordinator.schedule(deckID: 42, after: first)
        try coordinator.performNextMutation(deckID: 42) { advances += 1 }
        coordinator.schedule(deckID: 42, after: second)
        #expect(advances == 2 && rebuilds.isEmpty)
        try coordinator.flush(deckIDs: [42])
        #expect(rebuilds == [second])
    }

    @Test("navigation away leaves failed work at the root for Retry, with no later timer rebuild")
    func navigationAwayRetry() throws {
        var attempts = 0
        let coordinator = PendingNextCoordinator(rebuild: { _, _ in
            attempts += 1
            if attempts == 1 { throw Failure.lock }
        }, reload: {})
        coordinator.schedule(deckID: 42, after: .now)
        // Detail's disappearance asks the root coordinator to flush.
        #expect(throws: Failure.self) { try coordinator.flush(deckIDs: [42]) }
        #expect(coordinator.hasPending(deckID: 42))
        // The detail instance is gone; root Retry still has its anchor.
        try coordinator.retry()
        coordinator.expireTimer(deckID: 42)
        #expect(attempts == 2)
        #expect(!coordinator.hasPending(deckID: 42))
    }
}
