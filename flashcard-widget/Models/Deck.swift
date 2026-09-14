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

    /// While `true`, `DeckScheduler.next(...)` is a complete no-op and no
    /// code path regenerates this deck's queue (ADR 0002, decision 2).
    /// Defaults `false` -- every deck schedules by default, and any number
    /// of decks can be unpaused at once.
    var isPaused: Bool = false

    /// Monotonic per-deck counter `HistoryEntry.sequence` is drawn from.
    /// Starts at 1 so the deck's first-ever entry is `sequence == 1`.
    var nextHistorySequence: Int = 1

    /// The highest `sequence` value "Next" has ever advanced to for this
    /// deck. `nil` if Next has never been tapped -- deliberately distinct
    /// from "the pointer is `nil`" (ADR 0002, decision 4): a soft-delete
    /// pointer-clear leaves this at its old, non-`nil` value.
    var highestReachedSequence: Int?

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card] = []

    @Relationship(deleteRule: .cascade, inverse: \HistoryEntry.deck)
    var historyEntries: [HistoryEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \DisplayConfig.deck)
    var displayConfig: DisplayConfig?

    /// The pointer to this deck's current card. Remains in exactly two
    /// states: references an entry belonging to this deck, or `nil`. Not
    /// an owning relationship -- the entry's lifecycle is governed by
    /// `historyEntries` above.
    var activeHistoryEntry: HistoryEntry?

    init(ankiDeckID: Int64, name: String) {
        self.ankiDeckID = ankiDeckID
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Draws and advances the next `HistoryEntry.sequence` value for this
    /// deck.
    func consumeNextSequence() -> Int {
        let sequence = nextHistorySequence
        nextHistorySequence += 1
        return sequence
    }

    var activeCards: [Card] {
        cards.filter { $0.isActive }
    }

    /// True while any note type used by a (still active) card in this deck
    /// hasn't finished field-role mapping. Drives the "needs field mapping"
    /// badge required by the apkg-import spec.
    var needsFieldMapping: Bool {
        !noteTypesNeedingMapping.isEmpty
    }

    /// Distinct note types used by this deck's active cards, mapped or not.
    /// A note type's mapping is shared globally (keyed by `ankiNoteTypeID`,
    /// per ADR 0001 decision 4) -- editing it from one deck affects every
    /// other deck that reuses the same note type.
    var allNoteTypes: [NoteType] {
        var seen = Set<PersistentIdentifier>()
        var result: [NoteType] = []
        for card in activeCards {
            guard let noteType = card.note?.noteType else { continue }
            if seen.insert(noteType.persistentModelID).inserted {
                result.append(noteType)
            }
        }
        return result
    }

    /// Subset of `allNoteTypes` that still needs a field-role mapping.
    var noteTypesNeedingMapping: [NoteType] {
        allNoteTypes.filter { !$0.isFieldMappingComplete }
    }
}
