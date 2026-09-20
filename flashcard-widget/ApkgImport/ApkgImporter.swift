//
//  ApkgImporter.swift
//  flashcard-widget
//
//  Orchestrates a full `.apkg` import: load the zip, resolve+decompress the
//  collection database, parse it into container-agnostic structs, then
//  upsert SwiftData records. All parsing happens before any SwiftData
//  mutation, and any error during the mutation phase rolls the context
//  back -- so a failed import can never leave previously-imported data
//  changed (apkg-import spec).
//

import Foundation
import SwiftData

struct ApkgImportResult {
    /// Decks touched (created or updated) by this import.
    let deckIDs: [PersistentIdentifier]
    /// Newly-encountered note types (>=2 fields) that still need a
    /// field-role mapping prompt shown to the user.
    let noteTypesNeedingMapping: [PersistentIdentifier]
}

enum ApkgImporter {
    static func importApkg(fileURL: URL, modelContext: ModelContext) throws -> ApkgImportResult {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw ApkgImportError.notAnApkg
        }

        let package = try ApkgPackageLoader.load(fileData: fileData)
        let collection = try parseCollection(from: package)

        do {
            return try ScheduleFileLock.shared().withExclusiveLock {
                try apply(collection, package: package, to: modelContext)
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Collection parsing

    private static func parseCollection(from package: ApkgPackage) throws -> ParsedCollection {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        try package.sqliteData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let connection: SQLiteConnection
        do {
            connection = try SQLiteConnection(fileURL: tempURL)
        } catch {
            throw ApkgImportError.damagedCollection
        }

        do {
            let variant = try CollectionSchemaDetector.detect(connection)
            switch variant {
            case .legacy:
                return try LegacyCollectionParser.parse(connection)
            case .modern:
                return try ModernCollectionParser.parse(connection)
            }
        } catch let error as ApkgImportError {
            throw error
        } catch {
            throw ApkgImportError.damagedCollection
        }
    }

    // MARK: - SwiftData upsert

    private static func apply(_ collection: ParsedCollection, package: ApkgPackage, to modelContext: ModelContext) throws -> ApkgImportResult {
        var noteTypeByAnkiID: [Int64: NoteType] = [:]
        var newlyCreatedNoteTypes: [NoteType] = []

        for parsed in collection.noteTypes {
            if let existing = try fetchNoteType(ankiID: parsed.ankiID, in: modelContext) {
                existing.name = parsed.name
                syncFields(existing, with: parsed.fields, modelContext: modelContext)
                noteTypeByAnkiID[parsed.ankiID] = existing
            } else {
                let noteType = NoteType(ankiNoteTypeID: parsed.ankiID, name: parsed.name)
                modelContext.insert(noteType)
                for field in parsed.fields {
                    let noteTypeField = NoteTypeField(name: field.name, ordinal: field.ordinal)
                    noteTypeField.noteType = noteType
                    noteType.fields.append(noteTypeField)
                    modelContext.insert(noteTypeField)
                }
                // A single-field note type has nothing to disambiguate --
                // auto-map it and skip the mapping prompt entirely.
                if noteType.fields.count == 1 {
                    noteType.fields[0].role = .primary
                }
                noteTypeByAnkiID[parsed.ankiID] = noteType
                newlyCreatedNoteTypes.append(noteType)
            }
        }

        // Decks created for the first time by this import -- their initial
        // schedule can't be seeded here (no cards exist for them to pick
        // from yet); seeding happens later in this same call, once cards
        // have been upserted (ADR 0002, consequences).
        var newlyCreatedDecks: [Deck] = []

        let referencedDeckIDs = Set(collection.cards.map { $0.deckID })
        var deckByAnkiID: [Int64: Deck] = [:]
        for parsedDeck in collection.decks where referencedDeckIDs.contains(parsedDeck.ankiID) {
            if let existing = try fetchDeck(ankiID: parsedDeck.ankiID, in: modelContext) {
                existing.name = parsedDeck.name
                existing.updatedAt = Date()
                deckByAnkiID[parsedDeck.ankiID] = existing
            } else {
                let deck = Deck(ankiDeckID: parsedDeck.ankiID, name: parsedDeck.name)
                modelContext.insert(deck)
                deck.displayConfig = DisplayConfig()
                deckByAnkiID[parsedDeck.ankiID] = deck
                newlyCreatedDecks.append(deck)
            }
        }
        // Defensive fallback: a card can in principle reference a deck id
        // that's missing from the decks table entirely. Don't silently drop
        // the card -- surface it under a clearly-labeled placeholder deck.
        for deckID in referencedDeckIDs where deckByAnkiID[deckID] == nil {
            if let existing = try fetchDeck(ankiID: deckID, in: modelContext) {
                deckByAnkiID[deckID] = existing
            } else {
                let deck = Deck(ankiDeckID: deckID, name: "Unknown Deck")
                modelContext.insert(deck)
                deck.displayConfig = DisplayConfig()
                deckByAnkiID[deckID] = deck
                newlyCreatedDecks.append(deck)
            }
        }

        var noteByAnkiID: [Int64: Note] = [:]
        for parsedNote in collection.notes {
            let noteType = noteTypeByAnkiID[parsedNote.noteTypeID]
            let note: Note
            if let existing = try fetchNote(ankiID: parsedNote.ankiID, in: modelContext) {
                existing.fieldValues = parsedNote.fieldValues
                if let noteType { existing.noteType = noteType }
                existing.removedAt = nil
                existing.updatedAt = Date()
                note = existing
            } else {
                note = Note(ankiNoteID: parsedNote.ankiID, fieldValues: parsedNote.fieldValues, noteType: noteType)
                modelContext.insert(note)
            }
            noteByAnkiID[parsedNote.ankiID] = note
            MediaImporter.copyReferencedMedia(for: note, package: package, modelContext: modelContext)
        }

        var cardsByDeckInNewFile: [Int64: Set<Int64>] = [:]
        for parsedCard in collection.cards {
            cardsByDeckInNewFile[parsedCard.deckID, default: []].insert(parsedCard.ankiID)

            let note = noteByAnkiID[parsedCard.noteID]
            let deck = deckByAnkiID[parsedCard.deckID]
            if let existing = try fetchCard(ankiID: parsedCard.ankiID, in: modelContext) {
                existing.ordinal = parsedCard.ordinal
                if let note { existing.note = note }
                if let deck { existing.deck = deck }
                existing.removedAt = nil
                existing.updatedAt = Date()
            } else {
                let card = Card(ankiCardID: parsedCard.ankiID, ordinal: parsedCard.ordinal, note: note, deck: deck)
                modelContext.insert(card)
            }
        }

        // Seed each newly-created deck's initial schedule (10 `HistoryEntry`
        // rows via the empty-queue generation rule) now that its cards
        // exist -- this couldn't happen at either deck-creation site above,
        // which run before any card has been upserted for that deck yet
        // (ADR 0002, consequences). Still inside this same import
        // transaction/save.
        for deck in newlyCreatedDecks {
            try DeckScheduler.ensureSchedule(for: deck, in: modelContext, now: Date())
        }

        // Soft-delete reconciliation, scoped to decks this import actually
        // touched: any previously-known card in that deck absent from the
        // new file is flagged removed, never hard-deleted (ADR 0001,
        // decision 6). A note follows its cards into removal once none of
        // its cards remain active.
        let now = Date()
        var candidateNoteIDs: Set<PersistentIdentifier> = []
        var decksWithNewSoftDeletes: Set<PersistentIdentifier> = []
        for (deckAnkiID, newCardIDs) in cardsByDeckInNewFile {
            guard let deck = deckByAnkiID[deckAnkiID] else { continue }
            for existingCard in deck.cards where !newCardIDs.contains(existingCard.ankiCardID) {
                if existingCard.removedAt == nil {
                    existingCard.removedAt = now
                    existingCard.updatedAt = now
                    decksWithNewSoftDeletes.insert(deck.persistentModelID)
                }
                if let note = existingCard.note {
                    candidateNoteIDs.insert(note.persistentModelID)
                }
            }
        }
        for noteID in candidateNoteIDs {
            guard let note = modelContext.model(for: noteID) as? Note else { continue }
            let hasActiveCard = note.cards.contains { $0.removedAt == nil }
            if !hasActiveCard && note.removedAt == nil {
                note.removedAt = now
                note.updatedAt = now
            }
        }

        // Per deck that had at least one card soft-deleted just now:
        // discard its unreached queue (always, even paused), clear the
        // pointer if its own entry's card was among those soft-deleted,
        // then regenerate synchronously (unless paused, in which case
        // regeneration is deferred until unpaused and next read) --
        // ADR 0002, decision 5.
        for deckID in decksWithNewSoftDeletes {
            guard let deck = modelContext.model(for: deckID) as? Deck else { continue }
            DeckScheduler.handleSoftDelete(for: deck, in: modelContext)
        }

        try modelContext.save()

        let noteTypesNeedingMapping = newlyCreatedNoteTypes
            .filter { $0.fields.count >= 2 && !$0.isFieldMappingComplete }
            .map(\.persistentModelID)

        return ApkgImportResult(
            deckIDs: Array(deckByAnkiID.values.map(\.persistentModelID)),
            noteTypesNeedingMapping: noteTypesNeedingMapping
        )
    }

    private static func syncFields(_ noteType: NoteType, with parsedFields: [ParsedField], modelContext: ModelContext) {
        for field in parsedFields {
            if let existingField = noteType.fields.first(where: { $0.ordinal == field.ordinal }) {
                existingField.name = field.name
            } else {
                let noteTypeField = NoteTypeField(name: field.name, ordinal: field.ordinal)
                noteTypeField.noteType = noteType
                noteType.fields.append(noteTypeField)
                modelContext.insert(noteTypeField)
            }
        }
    }

    // MARK: - Fetch-by-Anki-ID helpers

    private static func fetchNoteType(ankiID: Int64, in modelContext: ModelContext) throws -> NoteType? {
        var descriptor = FetchDescriptor<NoteType>(predicate: #Predicate { $0.ankiNoteTypeID == ankiID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func fetchDeck(ankiID: Int64, in modelContext: ModelContext) throws -> Deck? {
        var descriptor = FetchDescriptor<Deck>(predicate: #Predicate { $0.ankiDeckID == ankiID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func fetchNote(ankiID: Int64, in modelContext: ModelContext) throws -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.ankiNoteID == ankiID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func fetchCard(ankiID: Int64, in modelContext: ModelContext) throws -> Card? {
        var descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.ankiCardID == ankiID })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
