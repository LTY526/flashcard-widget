//
//  ApkgImportError.swift
//  flashcard-widget
//
//  Error taxonomy required by the apkg-import spec: the user must see a
//  message specific to *which* failure occurred, never a single generic
//  "couldn't import".
//

import Foundation

enum ApkgImportError: Error, LocalizedError, Equatable {
    /// Not a zip file at all, or a zip that doesn't contain any of the
    /// collection file variants we know how to look for.
    case notAnApkg

    /// The zip opened and a collection file was found, but the database
    /// inside it is corrupt/unreadable (bad zstd frame, not a valid SQLite
    /// file, a query against expected tables fails, etc).
    case damagedCollection

    /// The collection database is readable, but its schema version is
    /// neither of the two variants this app understands.
    case unsupportedSchemaVersion

    var errorDescription: String? {
        switch self {
        case .notAnApkg:
            return "This doesn't look like an Anki deck file."
        case .damagedCollection:
            return "This deck file is damaged."
        case .unsupportedSchemaVersion:
            return "This deck was made with a version of Anki this app doesn't support yet."
        }
    }
}
