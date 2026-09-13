//
//  FieldMappingService.swift
//  flashcard-widget
//
//  Applies a user's (or heuristic default's) field-role mapping to a note
//  type. Mapping is stored on the note type itself, so it's remembered
//  across every deck that reuses this note type (apkg-import spec, ADR
//  0001 decision 4).
//

import Foundation

enum FieldMappingService {
    /// Assigns roles by field name. Fields named in neither set are left
    /// unmapped -- still stored, just unused by v1 display logic.
    static func applyMapping(to noteType: NoteType, primaryFieldNames: Set<String>, secondaryFieldNames: Set<String>) {
        for field in noteType.fields {
            if primaryFieldNames.contains(field.name) {
                field.role = .primary
            } else if secondaryFieldNames.contains(field.name) {
                field.role = .secondary
            } else {
                field.role = nil
            }
        }
    }

    /// A reasonable heuristic default for a fresh multi-field note type:
    /// first field is primary, the rest are secondary. Used only as a
    /// suggestion the mapping UI can pre-fill -- the user still has to
    /// confirm it for `isFieldMappingComplete` to become true, per spec
    /// ("user (or a heuristic default) maps fields").
    static func heuristicDefaultMapping(for noteType: NoteType) -> (primary: Set<String>, secondary: Set<String>) {
        let ordered = noteType.sortedFields
        guard let first = ordered.first else { return ([], []) }
        let rest = Set(ordered.dropFirst().map(\.name))
        return ([first.name], rest)
    }
}
