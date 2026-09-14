//
//  DisplayOrder.swift
//  flashcard-widget
//
//  The strategy a deck's `DisplayConfig` uses to pick the next card when
//  `DeckScheduler` generates a new queued `HistoryEntry` (ADR 0002,
//  decision 4). Only these two strategies are in scope for this round --
//  no additional strategies are planned within this spec.
//

import Foundation

enum DisplayOrder: String, Codable, CaseIterable, Sendable {
    case sequential
    case random
}
