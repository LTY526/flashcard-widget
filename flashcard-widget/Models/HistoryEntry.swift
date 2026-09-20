//
//  HistoryEntry.swift
//  flashcard-widget
//
//  One slot in a deck's own scheduled card queue/history (ADR 0002,
//  decision 4). `sequence` (monotonic per-deck, from
//  `Deck.nextHistorySequence`) is the only thing "next"/"previous" is ever
//  defined in terms of. ADR 0003 supersedes the old timestamp rule:
//  `projectedAt` derives due status but never identity/order. `card` is optional and nullify-on-delete (see
//  `Card.historyEntries`): a `HistoryEntry` whose card has been hard-deleted
//  (via `DeckRemover`'s cross-deck note cleanup) still exists and still
//  shows in History, just without card text to render.
//

import Foundation
import SwiftData

@Model
final class HistoryEntry {
    var sequence: Int = 0
    /// The wall-clock time this entry becomes, or became, its deck's
    /// current card. It derives due status; ordering remains `sequence`.
    var projectedAt: Date = Date()

    var card: Card?
    var deck: Deck?

    init(sequence: Int, projectedAt: Date, card: Card?, deck: Deck?) {
        self.sequence = sequence
        self.projectedAt = projectedAt
        self.card = card
        self.deck = deck
    }
}
