//
//  ModernCollectionParser.swift
//  flashcard-widget
//
//  Reads the modern relational schema used by `.anki21b`/`.anki21`:
//  dedicated `notetypes`/`fields`/`decks` tables instead of the legacy
//  JSON blobs. Per-notetype/per-deck config columns are protobuf-encoded
//  in real Anki collections; this v1 slice doesn't need their contents
//  (scheduling config, styling, etc. are out of scope), so we only select
//  the plain columns we do need and never touch those blobs.
//

import Foundation

enum ModernCollectionParser {
    static func parse(_ connection: SQLiteConnection) throws -> ParsedCollection {
        var noteTypes: [ParsedNoteType] = []
        for row in try connection.query("SELECT id, name FROM notetypes") {
            guard row.count == 2 else { continue }
            let noteTypeID = row[0].int64Value
            let name = row[1].stringValue

            var fields: [ParsedField] = []
            for fieldRow in try connection.query("SELECT ord, name FROM fields WHERE ntid = ? ORDER BY ord", bindings: [.int(noteTypeID)]) {
                guard fieldRow.count == 2 else { continue }
                fields.append(ParsedField(name: fieldRow[1].stringValue, ordinal: Int(fieldRow[0].int64Value)))
            }
            noteTypes.append(ParsedNoteType(ankiID: noteTypeID, name: name, fields: fields))
        }

        var decks: [ParsedDeck] = []
        for row in try connection.query("SELECT id, name FROM decks") {
            guard row.count == 2 else { continue }
            decks.append(ParsedDeck(ankiID: row[0].int64Value, name: row[1].stringValue))
        }

        var notes: [ParsedNote] = []
        for row in try connection.query("SELECT id, mid, flds FROM notes") {
            guard row.count == 3 else { continue }
            notes.append(ParsedNote(
                ankiID: row[0].int64Value,
                noteTypeID: row[1].int64Value,
                fieldValues: AnkiFieldFormat.splitFields(row[2].stringValue)
            ))
        }

        var cards: [ParsedCard] = []
        for row in try connection.query("SELECT id, nid, did, ord FROM cards") {
            guard row.count == 4 else { continue }
            cards.append(ParsedCard(
                ankiID: row[0].int64Value,
                noteID: row[1].int64Value,
                deckID: row[2].int64Value,
                ordinal: Int(row[3].int64Value)
            ))
        }

        return ParsedCollection(noteTypes: noteTypes, decks: decks, notes: notes, cards: cards)
    }
}
