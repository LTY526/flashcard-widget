//
//  NoteType.swift
//  flashcard-widget
//
//  Mirrors an Anki "note type" / "model": a named set of ordered fields
//  shared by every note created from it. `ankiNoteTypeID` is Anki's
//  upstream identifier and is how we recognize "this note type has been
//  seen before" across separate `.apkg` imports/decks (ADR 0001, decision 4
//  and the apkg-import spec's "remembered per note type" requirement).
//

import Foundation
import SwiftData

@Model
final class NoteType {
    @Attribute(.unique) var ankiNoteTypeID: Int64 = 0
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \NoteTypeField.noteType)
    var fields: [NoteTypeField] = []

    @Relationship(deleteRule: .nullify, inverse: \Note.noteType)
    var notes: [Note] = []

    init(ankiNoteTypeID: Int64, name: String) {
        self.ankiNoteTypeID = ankiNoteTypeID
        self.name = name
        self.createdAt = Date()
    }

    var sortedFields: [NoteTypeField] {
        fields.sorted { $0.ordinal < $1.ordinal }
    }

    /// A note type is considered "mapped" once at least a `primary` role has
    /// been assigned. Per spec, single-field note types are auto-mapped at
    /// creation time and so are always complete; multi-field note types stay
    /// incomplete until the user finishes (or the app defaults) the mapping
    /// prompt.
    var isFieldMappingComplete: Bool {
        fields.contains { $0.role == .primary }
    }
}
