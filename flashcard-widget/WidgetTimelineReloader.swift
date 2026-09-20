import Foundation
import WidgetKit

actor WidgetTimelineReloader {
    static let shared = WidgetTimelineReloader()

    private static let widgetKind = "FlashcardWidget"
    private static let debounceDelay: Duration = .milliseconds(600)

    private var pendingReload: Task<Void, Never>?

    func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task {
            do {
                try await Task.sleep(for: Self.debounceDelay)
                try Task.checkCancellation()
                WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
            } catch {
                // A newer request replaced this pending reload.
            }
        }
    }
}
