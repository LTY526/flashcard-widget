//
//  Deck.swift
//  flashcard-widget
//
//  `ankiDeckID` is Anki's upstream deck id. Re-importing an `.apkg` whose
//  collection contains the same deck id updates this row's cards/notes in
//  place instead of creating a duplicate deck (apkg-import spec).
//

import Foundation
import SwiftData

@Model
final class Deck {
    @Attribute(.unique) var ankiDeckID: Int64 = 0
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card] = []

    init(ankiDeckID: Int64, name: String) {
        self.ankiDeckID = ankiDeckID
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var activeCards: [Card] {
        cards.filter { $0.isActive }
    }

    /// True while any note type used by a (still active) card in this deck
    /// hasn't finished field-role mapping. Drives the "needs field mapping"
    /// badge required by the apkg-import spec.
    var needsFieldMapping: Bool {
        activeCards.contains { card in
            guard let noteType = card.note?.noteType else { return false }
            return !noteType.isFieldMappingComplete
        }
    }
}
