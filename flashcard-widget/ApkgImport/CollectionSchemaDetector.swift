//
//  CollectionSchemaDetector.swift
//  flashcard-widget
//
//  Determines which of the two schema shapes this app understands an
//  opened collection database actually uses, by probing for the tables
//  each shape requires -- never by trusting the zip entry's filename alone
//  (a modern export ships a dummy stub `collection.anki2` right alongside
//  the real `collection.anki21b`, so filename presence is not a reliable
//  signal; see apkg-import spec).
//

import Foundation

enum CollectionSchemaVariant {
    /// `collection.anki2`: single `col` row holding `models`/`decks` as
    /// JSON text; schema version 11.
    case legacy
    /// `collection.anki21`/`collection.anki21b`: dedicated relational
    /// `notetypes`/`fields`/`decks` tables.
    case modern
}

enum CollectionSchemaDetector {
    /// Only the legacy schema version this app was written against. Any
    /// other value is a version of Anki we don't support (older or newer).
    static let supportedLegacyVersion: Int64 = 11

    static func detect(_ connection: SQLiteConnection) throws -> CollectionSchemaVariant {
        let hasModernTables = try connection.tableExists("notetypes")
            && connection.tableExists("fields")
            && connection.tableExists("decks")
            && connection.tableExists("notes")
            && connection.tableExists("cards")
        if hasModernTables {
            return .modern
        }

        let hasCol = try connection.tableExists("col")
        let hasNotes = try connection.tableExists("notes")
        let hasCards = try connection.tableExists("cards")
        let hasLegacyTables = hasCol && hasNotes && hasCards
        guard hasLegacyTables else {
            // Opened fine as SQLite but doesn't look like any Anki
            // collection shape we recognize at all.
            throw ApkgImportError.damagedCollection
        }

        let rows = try connection.query("SELECT ver FROM col LIMIT 1")
        guard let versionColumn = rows.first?.first else {
            throw ApkgImportError.damagedCollection
        }
        guard versionColumn.int64Value == supportedLegacyVersion else {
            throw ApkgImportError.unsupportedSchemaVersion
        }
        return .legacy
    }
}
