//
//  ParsedCollection.swift
//  flashcard-widget
//
//  Container-format-agnostic result of reading an Anki collection database.
//  Both the legacy (.anki2) and modern (.anki21b) parsers produce this same
//  shape so the importer's upsert/reconciliation logic doesn't need to know
//  which container variant it came from.
//

import Foundation

struct ParsedField {
    let name: String
    let ordinal: Int
}

struct ParsedNoteType {
    let ankiID: Int64
    let name: String
    let fields: [ParsedField]
}

struct ParsedDeck {
    let ankiID: Int64
    let name: String
}

struct ParsedNote {
    let ankiID: Int64
    let noteTypeID: Int64
    /// Field values in field-ordinal order, split on Anki's 0x1F separator.
    let fieldValues: [String]
}

struct ParsedCard {
    let ankiID: Int64
    let noteID: Int64
    let deckID: Int64
    let ordinal: Int
}

struct ParsedCollection {
    var noteTypes: [ParsedNoteType]
    var decks: [ParsedDeck]
    var notes: [ParsedNote]
    var cards: [ParsedCard]
}

enum AnkiFieldFormat {
    /// Anki joins a note's field values with 0x1F (ASCII Unit Separator).
    static let fieldSeparator: Character = "\u{1f}"

    static func splitFields(_ raw: String) -> [String] {
        raw.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
    }
}
