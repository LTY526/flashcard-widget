//
//  CardWidgetViewTests.swift
//  flashcard-widgetTests
//

import Testing
@testable import flashcard_widget

struct CardWidgetViewTests {
    @Test("tertiary-mapped fields are aggregated like primary and secondary fields")
    func tertiaryTextAggregatesMappedFields() throws {
        let noteType = NoteType(ankiNoteTypeID: 1, name: "Japanese Vocab")
        let expression = NoteTypeField(name: "Expression", ordinal: 0, role: .primary)
        let reading = NoteTypeField(name: "Reading", ordinal: 1, role: .tertiary)
        let meaning = NoteTypeField(name: "Meaning", ordinal: 2, role: .tertiary)
        expression.noteType = noteType
        reading.noteType = noteType
        meaning.noteType = noteType
        noteType.fields = [meaning, expression, reading]

        let note = Note(
            ankiNoteID: 1,
            fieldValues: ["犬", "<b>いぬ</b>", "dog"],
            noteType: noteType
        )

        #expect(note.tertiaryText == "いぬ / dog")
    }

    @Test("card content selects independent primary, secondary, and tertiary text")
    func selectsAllProvidedText() {
        let content = CardWidgetContent.resolve(
            primary: "犬",
            secondary: "dog",
            tertiary: "いぬ"
        )

        #expect(content.primary == "犬")
        #expect(content.secondary == "dog")
        #expect(content.tertiary == "いぬ")
        #expect(!content.usesPrimaryPlaceholder)
    }

    @Test("card content omits nil optional sections")
    func omitsNilOptionalSections() {
        let withoutSecondary = CardWidgetContent.resolve(
            primary: "犬",
            secondary: nil,
            tertiary: "いぬ"
        )
        let withoutTertiary = CardWidgetContent.resolve(
            primary: "犬",
            secondary: "dog",
            tertiary: nil
        )

        #expect(withoutSecondary.secondary == nil)
        #expect(withoutSecondary.tertiary == "いぬ")
        #expect(withoutTertiary.secondary == "dog")
        #expect(withoutTertiary.tertiary == nil)
    }

    @Test("card content substitutes a clear placeholder for nil primary text")
    func substitutesPrimaryPlaceholder() {
        let content = CardWidgetContent.resolve(
            primary: nil,
            secondary: "dog",
            tertiary: nil
        )

        #expect(content.primary == "No field mapped to Primary yet")
        #expect(content.usesPrimaryPlaceholder)
    }
}
