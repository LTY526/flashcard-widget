import SwiftData
import SwiftUI

@main
struct flashcard_widgetApp: App {
    private let sharedModelContainer: ModelContainer?
    private let libraryError: String?

    init() {
        do {
            sharedModelContainer = try SharedModelContainer.makeShared()
            libraryError = nil
        } catch {
            sharedModelContainer = nil
            libraryError = String(describing: error)
            print("Unable to open shared library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let sharedModelContainer {
                ContentView()
                    .modelContainer(sharedModelContainer)
            } else {
                ContentUnavailableView(
                    "Unable to Open Library",
                    systemImage: "exclamationmark.triangle",
                    description: Text(libraryError ?? "Flashcards are unavailable. Please reopen the app.")
                )
            }
        }
    }
}
