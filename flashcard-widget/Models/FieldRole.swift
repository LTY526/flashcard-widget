//
//  FieldRole.swift
//  flashcard-widget
//
//  Semantic display role a note type's field can be mapped to. Mapping is
//  user/deck-configured per ADR 0001 (decision 4) rather than the app
//  assuming fixed field names like "Expression"/"Meaning".
//

import Foundation

enum FieldRole: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
}
