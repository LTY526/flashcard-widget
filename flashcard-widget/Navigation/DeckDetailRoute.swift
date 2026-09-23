import Foundation

/// Navigation and subsection selection are independent of a schedule snapshot.
struct DeckDetailRoute {
    enum Mode: String, CaseIterable, Identifiable {
        case current = "Current"
        case schedule = "Schedule"
        case config = "Config"
        var id: Self { self }
    }

    var path: [Int64] = []
    var mode: Mode = .current
    var scheduleTab: DeckHistoryView.Tab = .upcoming
    private(set) var requestedDeepLinkID: Int64?

    mutating func open(_ id: Int64) {
        path = [id]
        mode = .current
        scheduleTab = .upcoming
    }

    mutating func openDeepLink(_ id: Int64?) {
        guard let id else {
            path = []
            mode = .current
            return
        }
        if path != [id] { path = [id]; scheduleTab = .upcoming }
        mode = .current
    }

    mutating func requestDeepLink(_ id: Int64?) {
        requestedDeepLinkID = id
        if id == nil { openDeepLink(nil) }
    }

    mutating func resolveRequestedDeepLink(exists: Bool) {
        guard let id = requestedDeepLinkID else { return }
        requestedDeepLinkID = nil
        openDeepLink(exists ? id : nil)
    }

    mutating func select(_ selectedMode: Mode) { mode = selectedMode }
}
