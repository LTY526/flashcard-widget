//
//  ApkgImportTests.swift
//  flashcard-widgetTests
//
//  Acceptance tests for docs/specs/apkg-import.md.
//

import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([Deck.self, NoteType.self, NoteTypeField.self, Note.self, Card.self, MediaItem.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}

@MainActor
private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
    try context.fetch(FetchDescriptor<T>())
}

@MainActor
@Suite("apkg import")
struct ApkgImportTests {

    // MARK: - Both container variants produce expected records

    @Test("legacy .anki2 container imports decks/note types/notes/cards")
    func importLegacyContainer() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("legacy_deck"), modelContext: context)

        let decks = try fetchAll(Deck.self, in: context)
        #expect(decks.count == 1)
        let deck = try #require(decks.first)
        #expect(deck.name == "Japanese Vocab::Legacy Deck")
        #expect(deck.ankiDeckID == 1_700_000_000_010)

        let noteTypes = try fetchAll(NoteType.self, in: context)
        #expect(noteTypes.count == 1)
        let noteType = try #require(noteTypes.first)
        #expect(noteType.name == "Japanese Vocab")
        #expect(noteType.sortedFields.map(\.name) == ["Expression", "Reading", "Meaning"])

        let notes = try fetchAll(Note.self, in: context)
        #expect(notes.count == 2)
        let dogNote = try #require(notes.first { $0.fieldValues.first == "犬" })
        #expect(dogNote.fieldValues == ["犬", "いぬ", "dog [sound:dog.mp3]"])

        let cards = try fetchAll(Card.self, in: context)
        #expect(cards.count == 2)
        #expect(cards.allSatisfy { $0.deck?.ankiDeckID == 1_700_000_000_010 })
        #expect(cards.allSatisfy { $0.isActive })
    }

    @Test("modern .anki21b (zstd) container imports decks/note types/notes/cards")
    func importModernContainer() throws {
        let context = try makeInMemoryContext()
        let result = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck"), modelContext: context)

        let decks = try fetchAll(Deck.self, in: context)
        #expect(decks.count == 1)
        let deck = try #require(decks.first)
        #expect(deck.name == "Japanese Vocab::Modern Deck")
        #expect(deck.ankiDeckID == 1_700_000_000_020)

        let noteTypes = try fetchAll(NoteType.self, in: context)
        #expect(noteTypes.count == 1)
        #expect(noteTypes.first?.sortedFields.map(\.name) == ["Expression", "Reading", "Meaning"])

        let notes = try fetchAll(Note.self, in: context)
        #expect(notes.count == 2)

        let cards = try fetchAll(Card.self, in: context)
        #expect(cards.count == 2)

        // Multi-field note type isn't auto-mapped; the import result should
        // flag it for the field-mapping prompt.
        #expect(!result.noteTypesNeedingMapping.isEmpty)
        #expect(deck.needsFieldMapping)
    }

    // MARK: - Re-import reconciliation (soft delete)

    @Test("re-importing a deck with a note+card removed soft-deletes them")
    func reimportSoftDeletesRemovedNoteAndCard() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck"), modelContext: context)

        let decksBefore = try fetchAll(Deck.self, in: context)
        #expect(decksBefore.count == 1)
        let notesBefore = try fetchAll(Note.self, in: context)
        #expect(notesBefore.count == 2)

        // Re-import a modified copy of the same deck (same Anki deck id)
        // with the "neko" note and its card removed.
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck_removed"), modelContext: context)

        // Still exactly one deck -- updated in place, not duplicated.
        let decksAfter = try fetchAll(Deck.self, in: context)
        #expect(decksAfter.count == 1)

        let allNotes = try fetchAll(Note.self, in: context)
        #expect(allNotes.count == 2, "the removed note's row must still exist")
        let removedNote = try #require(allNotes.first { $0.fieldValues.first == "猫" })
        #expect(removedNote.removedAt != nil, "removed note must be flagged removed, not deleted")

        let survivingNote = try #require(allNotes.first { $0.fieldValues.first == "犬" })
        #expect(survivingNote.removedAt == nil)

        let allCards = try fetchAll(Card.self, in: context)
        #expect(allCards.count == 2, "the removed card's row must still exist")
        let removedCard = try #require(allCards.first { $0.note?.fieldValues.first == "猫" })
        #expect(removedCard.removedAt != nil)

        // Excluded from "active" queries.
        let activeNotes = allNotes.filter { $0.isActive }
        #expect(activeNotes.count == 1)
        #expect(activeNotes.first?.fieldValues.first == "犬")

        let activeCards = allCards.filter { $0.isActive }
        #expect(activeCards.count == 1)

        let deck = try #require(decksAfter.first)
        #expect(deck.activeCards.count == 1)
    }

    // MARK: - Multiple decks coexist

    @Test("importing a second, different apkg adds its deck alongside an already-imported one")
    func multipleDecksCoexist() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("legacy_deck"), modelContext: context)
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck"), modelContext: context)

        let decks = try fetchAll(Deck.self, in: context)
        #expect(decks.count == 2)
        let names = Set(decks.map(\.name))
        #expect(names == ["Japanese Vocab::Legacy Deck", "Japanese Vocab::Modern Deck"])

        // Both fixtures use the same underlying Anki note type id, so it
        // must be recognized as already-seen rather than duplicated.
        let noteTypes = try fetchAll(NoteType.self, in: context)
        #expect(noteTypes.count == 1)
    }

    // MARK: - Field mapping

    @Test("field mapping is remembered per note type across decks that reuse it")
    func fieldMappingRememberedAcrossDecks() throws {
        let context = try makeInMemoryContext()
        let firstImport = try ApkgImporter.importApkg(fileURL: Fixtures.url("legacy_deck"), modelContext: context)

        #expect(firstImport.noteTypesNeedingMapping.count == 1)
        let noteTypeID = try #require(firstImport.noteTypesNeedingMapping.first)
        let noteType = try #require(context.model(for: noteTypeID) as? NoteType)
        FieldMappingService.applyMapping(to: noteType, primaryFieldNames: ["Expression"], secondaryFieldNames: ["Reading", "Meaning"])
        try context.save()
        #expect(noteType.isFieldMappingComplete)

        // Importing a second deck that reuses this note type should not
        // ask for mapping again.
        let secondImport = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck"), modelContext: context)
        #expect(secondImport.noteTypesNeedingMapping.isEmpty)

        let decks = try fetchAll(Deck.self, in: context)
        let modernDeck = try #require(decks.first { $0.ankiDeckID == 1_700_000_000_020 })
        #expect(!modernDeck.needsFieldMapping)
    }

    @Test("a single-field note type auto-maps to primary and never needs the mapping prompt")
    func singleFieldNoteTypeAutoMaps() throws {
        let context = try makeInMemoryContext()
        let result = try ApkgImporter.importApkg(fileURL: Fixtures.url("single_field_deck"), modelContext: context)

        #expect(result.noteTypesNeedingMapping.isEmpty)

        let noteTypes = try fetchAll(NoteType.self, in: context)
        let noteType = try #require(noteTypes.first { $0.name == "Simple Fact" })
        #expect(noteType.fields.count == 1)
        #expect(noteType.fields.first?.role == .primary)
        #expect(noteType.isFieldMappingComplete)

        let decks = try fetchAll(Deck.self, in: context)
        #expect(decks.first?.needsFieldMapping == false)
    }

    @Test("dismissing the mapping prompt still imports notes/cards and leaves the deck flagged")
    func skippedMappingStillImports() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck"), modelContext: context)

        // Simulate the user dismissing the prompt: no mapping is applied.
        let notes = try fetchAll(Note.self, in: context)
        #expect(notes.count == 2)
        let cards = try fetchAll(Card.self, in: context)
        #expect(cards.count == 2)

        let decks = try fetchAll(Deck.self, in: context)
        #expect(decks.first?.needsFieldMapping == true)
    }

    // MARK: - Media

    @Test("media referenced by a note's fields is copied into app storage and associated with the note")
    func mediaIsCopiedAndAssociated() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("legacy_deck"), modelContext: context)

        let notes = try fetchAll(Note.self, in: context)
        let dogNote = try #require(notes.first { $0.fieldValues.first == "犬" })
        #expect(dogNote.mediaItems.count == 1)
        let mediaItem = try #require(dogNote.mediaItems.first)
        #expect(mediaItem.ankiFilename == "dog.mp3")

        let fileURL = MediaImporter.storageDirectory().appendingPathComponent(mediaItem.relativeStoragePath)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Error taxonomy

    @Test("a non-zip file produces a specific 'not an Anki deck' error")
    func notAZipProducesSpecificError() throws {
        let context = try makeInMemoryContext()
        #expect(throws: ApkgImportError.notAnApkg) {
            _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("not_a_zip"), modelContext: context)
        }
    }

    @Test("a zip missing the collection file produces a specific 'not an Anki deck' error")
    func missingCollectionProducesSpecificError() throws {
        let context = try makeInMemoryContext()
        #expect(throws: ApkgImportError.notAnApkg) {
            _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("missing_collection"), modelContext: context)
        }
    }

    @Test("a corrupt collection database produces a specific 'damaged file' error")
    func damagedCollectionProducesSpecificError() throws {
        let context = try makeInMemoryContext()
        #expect(throws: ApkgImportError.damagedCollection) {
            _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("damaged_collection"), modelContext: context)
        }
    }

    @Test("an unsupported schema version produces a specific 'unsupported version' error")
    func unsupportedVersionProducesSpecificError() throws {
        let context = try makeInMemoryContext()
        #expect(throws: ApkgImportError.unsupportedSchemaVersion) {
            _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("unsupported_version"), modelContext: context)
        }
    }

    @Test("the three error cases have distinct, specific messages")
    func errorMessagesAreDistinct() {
        let messages = Set([
            ApkgImportError.notAnApkg.errorDescription,
            ApkgImportError.damagedCollection.errorDescription,
            ApkgImportError.unsupportedSchemaVersion.errorDescription,
        ])
        #expect(messages.count == 3)
    }

    @Test("a failed import never mutates previously-imported data")
    func failedImportDoesNotMutateExistingData() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("legacy_deck"), modelContext: context)

        let decksBefore = try fetchAll(Deck.self, in: context)
        let notesBefore = try fetchAll(Note.self, in: context)
        let cardsBefore = try fetchAll(Card.self, in: context)

        #expect(throws: ApkgImportError.self) {
            _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("damaged_collection"), modelContext: context)
        }

        let decksAfter = try fetchAll(Deck.self, in: context)
        let notesAfter = try fetchAll(Note.self, in: context)
        let cardsAfter = try fetchAll(Card.self, in: context)

        #expect(decksBefore.count == decksAfter.count)
        #expect(notesBefore.count == notesAfter.count)
        #expect(cardsBefore.count == cardsAfter.count)
    }
}
