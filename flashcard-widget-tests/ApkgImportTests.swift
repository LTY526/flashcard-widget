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
    let schema = Schema([Deck.self, NoteType.self, NoteTypeField.self, Note.self, Card.self, MediaItem.self, DisplayConfig.self, HistoryEntry.self])
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
    private actor ReloadCounter {
        private(set) var count = 0
        func request() { count += 1 }
    }

    @Test("successful import and re-import each request one widget reload; failure requests none")
    func importReloadOrchestration() async throws {
        enum Failure: Error { case expected }
        let counter = ReloadCounter()

        _ = await ImportOperation.run({ "import" }, reload: { await counter.request() })
        #expect(await counter.count == 1)
        _ = await ImportOperation.run({ "re-import" }, reload: { await counter.request() })
        #expect(await counter.count == 2)
        await #expect(throws: Failure.self) {
            _ = try await ImportOperation.run({ throw Failure.expected }, reload: { await counter.request() })
        }
        #expect(await counter.count == 2)
    }

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

    // MARK: - Per-deck DisplayConfig + initial schedule (active-card-deck-management spec)

    @Test("every deck created by import -- via the main upsert loop or the Unknown Deck fallback branch -- gets exactly one DisplayConfig and 10 seeded HistoryEntry rows")
    func everyCreatedDeckGetsConfigAndSeededSchedule() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("unknown_deck_fallback"), modelContext: context)

        let decks = try fetchAll(Deck.self, in: context)
        #expect(decks.count == 2, "one deck from the main upsert loop, one from the Unknown Deck fallback branch")

        let knownDeck = try #require(decks.first { $0.name == "Known Deck" })
        let unknownDeck = try #require(decks.first { $0.name == "Unknown Deck" })

        for deck in [knownDeck, unknownDeck] {
            let configs = try fetchAll(DisplayConfig.self, in: context).filter { $0.deck?.persistentModelID == deck.persistentModelID }
            #expect(configs.count == 1, "\(deck.name) must have exactly one DisplayConfig")
            #expect(deck.displayConfig != nil)
            #expect(deck.displayConfig?.order == .sequential)
            #expect(deck.displayConfig?.intervalMinutes == 30)
            #expect(deck.displayConfig?.newCardsADay == 0)
            #expect(deck.displayConfig?.reviewPreviousDayCards == false)

            #expect(deck.historyEntries.count == 11, "\(deck.name) must have one current and 10 scheduled entries")
        }
    }

    @Test("re-importing into an already-existing deck does not create a second DisplayConfig or reseed its schedule")
    func reimportDoesNotDuplicateConfigOrReseed() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("unknown_deck_fallback"), modelContext: context)

        let deckBefore = try #require(try fetchAll(Deck.self, in: context).first { $0.name == "Known Deck" })
        let originalEntryIDs = Set(deckBefore.historyEntries.map(\.persistentModelID))
        #expect(originalEntryIDs.count == 11)

        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("unknown_deck_fallback"), modelContext: context)

        let decksAfter = try fetchAll(Deck.self, in: context)
        #expect(decksAfter.count == 2, "re-importing must not duplicate decks")

        let deckAfter = try #require(decksAfter.first { $0.name == "Known Deck" })
        let configs = try fetchAll(DisplayConfig.self, in: context).filter { $0.deck?.persistentModelID == deckAfter.persistentModelID }
        #expect(configs.count == 1, "still exactly one DisplayConfig, not two")

        let entryIDsAfter = Set(deckAfter.historyEntries.map(\.persistentModelID))
        #expect(entryIDsAfter == originalEntryIDs, "schedule wasn't reseeded -- original 10 entries' identities are unchanged")
    }

    @Test("re-importing a fixture with the deck's current card removed clears the pointer but keeps the HistoryEntry row, and regenerates the queue")
    func reimportSoftDeletingCurrentCardClearsPointerAndRegenerates() throws {
        let context = try makeInMemoryContext()
        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck"), modelContext: context)
        let deck = try #require(try fetchAll(Deck.self, in: context).first)

        // Drive Next until the current card is the "猫" note's card (the one
        // the removed fixture soft-deletes) -- only two active cards exist,
        // so at most two taps are needed.
        DeckScheduler.next(deck, in: context)
        if deck.activeHistoryEntry?.card?.note?.fieldValues.first != "猫" {
            DeckScheduler.next(deck, in: context)
        }
        let currentEntry = try #require(deck.activeHistoryEntry)
        #expect(currentEntry.card?.note?.fieldValues.first == "猫")

        _ = try ApkgImporter.importApkg(fileURL: Fixtures.url("modern_deck_removed"), modelContext: context)

        #expect(deck.activeHistoryEntry == nil, "pointer cleared since its card was soft-deleted")

        let allEntries = try fetchAll(HistoryEntry.self, in: context)
        #expect(allEntries.contains { $0.persistentModelID == currentEntry.persistentModelID }, "the old current entry's row still exists")
        #expect(currentEntry.card == nil || currentEntry.card?.isActive == false)

        let unreached = deck.historyEntries.filter { $0.sequence > (deck.highestReachedSequence ?? 0) }
        #expect(unreached.count == 10, "queue regenerated back to 10, synchronously")

        // A subsequent Next consumes a freshly generated entry, not any
        // pre-existing one.
        let unreachedIDsBeforeNext = Set(unreached.map(\.persistentModelID))
        DeckScheduler.next(deck, in: context)
        let newCurrent = try #require(deck.activeHistoryEntry)
        #expect(unreachedIDsBeforeNext.contains(newCurrent.persistentModelID))
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
