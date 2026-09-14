//
//  Card.swift
//  flashcard-widget
//
//  Links a note to a deck, preserving Anki's card ordinal (which template
//  on the note type this card renders). Cards are never hard-deleted, only
//  soft-deleted via `removedAt` (ADR 0001, decision 6).
//

import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var ankiCardID: Int64 = 0
    var ordinal: Int = 0
    var removedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var note: Note?
    var deck: Deck?

    /// `HistoryEntry` rows (in any deck) that reference this card.
    /// Nullify-on-delete: hard-deleting a card (e.g. via `DeckRemover`'s
    /// cross-deck note cleanup) leaves referencing entries in place with
    /// `card == nil` rather than cascading their deletion (ADR 0002,
    /// consequences).
    @Relationship(deleteRule: .nullify, inverse: \HistoryEntry.card)
    var historyEntries: [HistoryEntry] = []

    init(ankiCardID: Int64, ordinal: Int, note: Note?, deck: Deck?) {
        self.ankiCardID = ankiCardID
        self.ordinal = ordinal
        self.note = note
        self.deck = deck
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isActive: Bool { removedAt == nil }
}
