import Foundation
import SwiftData

enum SharedModelContainer {
    static let appGroupIdentifier = "group.com.xyz7172.flashcard-widget"
    static let storeFileName = "Flashcards.store"

    static let schema = Schema([
        Deck.self,
        NoteType.self,
        NoteTypeField.self,
        Note.self,
        Card.self,
        MediaItem.self,
        DisplayConfig.self,
        HistoryEntry.self
    ])

    static func make(at storeURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeShared() throws -> ModelContainer {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedStoreError.groupContainerUnavailable
        }
        return try make(at: groupURL.appendingPathComponent(storeFileName))
    }
}

enum SharedStoreError: Error {
    case groupContainerUnavailable
}
