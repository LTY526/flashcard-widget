//
//  NoteTypeField.swift
//  flashcard-widget
//

import Foundation
import SwiftData

@Model
final class NoteTypeField {
    var name: String = ""
    var ordinal: Int = 0
    var roleRawValue: String?

    var noteType: NoteType?

    init(name: String, ordinal: Int, role: FieldRole? = nil) {
        self.name = name
        self.ordinal = ordinal
        self.roleRawValue = role?.rawValue
    }

    var role: FieldRole? {
        get { roleRawValue.flatMap(FieldRole.init(rawValue:)) }
        set { roleRawValue = newValue?.rawValue }
    }
}
