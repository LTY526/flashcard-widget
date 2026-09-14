//
//  Note.swift
//  flashcard-widget
//
//  A note holds the actual field content; cards only reference a note plus
//  a template ordinal (a card has no displayable content of its own). Notes
//  are never hard-deleted -- `removedAt` marks a note that no longer exists
//  in the most recently imported version of its deck (ADR 0001, decision 6).
//

import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var ankiNoteID: Int64 = 0
    var fieldValues: [String] = []
    var removedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var noteType: NoteType?

    @Relationship(deleteRule: .cascade, inverse: \Card.note)
    var cards: [Card] = []

    @Relationship(deleteRule: .cascade, inverse: \MediaItem.note)
    var mediaItems: [MediaItem] = []

    init(ankiNoteID: Int64, fieldValues: [String], noteType: NoteType?) {
        self.ankiNoteID = ankiNoteID
        self.fieldValues = fieldValues
        self.noteType = noteType
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isActive: Bool { removedAt == nil }

    private func text(for role: FieldRole) -> String? {
        guard let noteType else { return nil }
        let values: [String] = noteType.sortedFields.compactMap { field in
            guard field.role == role, field.ordinal >= 0, field.ordinal < fieldValues.count else { return nil }
            return Self.plainText(from: fieldValues[field.ordinal])
        }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " / ")
    }

    var primaryText: String? { text(for: .primary) }
    var secondaryText: String? { text(for: .secondary) }

    /// Anki field values are stored as HTML fragments (e.g. `<br>`, `&nbsp;`,
    /// `<b>`) -- strip markup and decode common entities so display text
    /// reads as plain text instead of showing raw tags.
    static func plainText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression, range: nil)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
