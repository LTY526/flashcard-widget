import AppIntents
import SwiftData
import WidgetKit

struct DeckEntity: AppEntity {
    typealias ID = String
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Deck")
    static let defaultQuery = DeckEntityQuery()

    let ankiDeckID: Int64
    let name: String

    var id: String { String(ankiDeckID) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct DeckEntityQuery: EntityQuery {
    func entities(for identifiers: [DeckEntity.ID]) async throws -> [DeckEntity] {
        let entities = try await fetchDecks()
        let entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        return identifiers.compactMap { entitiesByID[$0] }
    }

    func suggestedEntities() async throws -> [DeckEntity] {
        try await fetchDecks()
    }

    private func fetchDecks() async throws -> [DeckEntity] {
        let lock = try ScheduleFileLock.shared()
        return try await lock.withLock(mode: .shared) {
            let container = try SharedModelContainer.makeShared()
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Deck>()
            descriptor.sortBy = [SortDescriptor(\.name), SortDescriptor(\.ankiDeckID)]
            return try context.fetch(descriptor).map {
                DeckEntity(ankiDeckID: $0.ankiDeckID, name: $0.name)
            }
        }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Flashcard Deck"
    static let description = IntentDescription("Choose the deck shown by this widget.")

    @Parameter(title: "Deck")
    var deck: DeckEntity?
}
