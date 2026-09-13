//
//  LegacyCollectionParser.swift
//  flashcard-widget
//
//  Reads the legacy `.anki2` schema (schema version 11): a single `col` row
//  stores decks and note types ("models") as JSON text; `notes`/`cards` are
//  plain relational tables. This only depends on Foundation's JSON decoder
//  and our own SQLite wrapper -- no Anki source is used.
//

import Foundation

enum LegacyCollectionParser {
    static func parse(_ connection: SQLiteConnection) throws -> ParsedCollection {
        let colRows = try connection.query("SELECT models, decks FROM col LIMIT 1")
        guard let colRow = colRows.first, colRow.count == 2 else {
            throw ApkgImportError.damagedCollection
        }
        let modelsJSON = colRow[0].stringValue
        let decksJSON = colRow[1].stringValue

        let noteTypes = try parseNoteTypes(fromJSON: modelsJSON)
        let decks = try parseDecks(fromJSON: decksJSON)

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

    private static func parseNoteTypes(fromJSON json: String) throws -> [ParsedNoteType] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApkgImportError.damagedCollection
        }
        var result: [ParsedNoteType] = []
        for (key, value) in object {
            guard let dict = value as? [String: Any] else { continue }
            let id = (dict["id"] as? NSNumber)?.int64Value ?? Int64(key) ?? 0
            let name = dict["name"] as? String ?? "Untitled"
            let fieldsArray = dict["flds"] as? [[String: Any]] ?? []
            let fields = fieldsArray.enumerated().map { index, fieldDict -> ParsedField in
                let ord = (fieldDict["ord"] as? NSNumber)?.intValue ?? index
                let name = fieldDict["name"] as? String ?? "Field \(index + 1)"
                return ParsedField(name: name, ordinal: ord)
            }
            result.append(ParsedNoteType(ankiID: id, name: name, fields: fields))
        }
        return result
    }

    private static func parseDecks(fromJSON json: String) throws -> [ParsedDeck] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApkgImportError.damagedCollection
        }
        var result: [ParsedDeck] = []
        for (key, value) in object {
            guard let dict = value as? [String: Any] else { continue }
            let id = (dict["id"] as? NSNumber)?.int64Value ?? Int64(key) ?? 0
            let name = dict["name"] as? String ?? "Untitled Deck"
            result.append(ParsedDeck(ankiID: id, name: name))
        }
        return result
    }
}
