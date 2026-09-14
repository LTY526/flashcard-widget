//
//  DeckRemoverTests.swift
//  flashcard-widgetTests
//
//  Acceptance tests for docs/specs/apkg-import.md's deck-removal criteria.
//  Builds the SwiftData graph directly (rather than through a .apkg
//  fixture) so the shared-note / soft-deleted-elsewhere edge cases can be
//  set up precisely.
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
private func makeDeck(ankiID: Int64, name: String, in context: ModelContext) -> Deck {
    let deck = Deck(ankiDeckID: ankiID, name: name)
    context.insert(deck)
    return deck
}

@MainActor
private func makeNote(ankiID: Int64, fieldValues: [String], in context: ModelContext) -> Note {
    let note = Note(ankiNoteID: ankiID, fieldValues: fieldValues, noteType: nil)
    context.insert(note)
    return note
}

@MainActor
private func makeCard(ankiID: Int64, note: Note, deck: Deck, removed: Bool = false, in context: ModelContext) -> Card {
    let card = Card(ankiCardID: ankiID, ordinal: 0, note: note, deck: deck)
    if removed { card.removedAt = Date() }
    context.insert(card)
    return card
}

@MainActor
private func makeMediaFile(for note: Note, filename: String, in context: ModelContext) throws -> URL {
    let relativePath = "Media/deckremovertest_\(UUID().uuidString)_\(filename)"
    let url = MediaImporter.storageDirectory().appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("test".utf8).write(to: url)
    let mediaItem = MediaItem(ankiFilename: filename, relativeStoragePath: relativePath, note: note)
    context.insert(mediaItem)
    return url
}

@MainActor
@Suite("deck removal")
struct DeckRemoverTests {

    @Test("removing a deck deletes its cards")
    func removesCards() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, name: "Deck A", in: context)
        let note = makeNote(ankiID: 1, fieldValues: ["front"], in: context)
        _ = makeCard(ankiID: 1, note: note, deck: deck, in: context)
        try context.save()

        try DeckRemover.remove(deck, from: context)

        let cards = try fetchAll(Card.self, in: context)
        #expect(cards.isEmpty)
    }

    @Test("a note used only by the removed deck is hard-deleted along with its media file on disk")
    func deletesNoteAndMediaWhenNotShared() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, name: "Deck A", in: context)
        let note = makeNote(ankiID: 1, fieldValues: ["front"], in: context)
        _ = makeCard(ankiID: 1, note: note, deck: deck, in: context)
        let mediaURL = try makeMediaFile(for: note, filename: "sound.mp3", in: context)
        try context.save()
        #expect(FileManager.default.fileExists(atPath: mediaURL.path))

        try DeckRemover.remove(deck, from: context)

        let notes = try fetchAll(Note.self, in: context)
        #expect(notes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: mediaURL.path))
    }

    @Test("a note with an active card in another deck survives removal, untouched, media intact")
    func preservesNoteSharedByActiveCardElsewhere() throws {
        let context = try makeInMemoryContext()
        let deckA = makeDeck(ankiID: 1, name: "Deck A", in: context)
        let deckB = makeDeck(ankiID: 2, name: "Deck B", in: context)
        let note = makeNote(ankiID: 1, fieldValues: ["front"], in: context)
        _ = makeCard(ankiID: 1, note: note, deck: deckA, in: context)
        _ = makeCard(ankiID: 2, note: note, deck: deckB, in: context)
        let mediaURL = try makeMediaFile(for: note, filename: "sound.mp3", in: context)
        try context.save()
        defer { try? FileManager.default.removeItem(at: mediaURL) }

        try DeckRemover.remove(deckA, from: context)

        let notes = try fetchAll(Note.self, in: context)
        #expect(notes.count == 1)
        #expect(notes.first?.removedAt == nil)
        #expect(FileManager.default.fileExists(atPath: mediaURL.path))
    }

    @Test("a note whose only other card is soft-deleted is still hard-deleted, not treated as shared")
    func deletesNoteWhoseOnlyOtherCardIsSoftDeleted() throws {
        let context = try makeInMemoryContext()
        let deckA = makeDeck(ankiID: 1, name: "Deck A", in: context)
        let deckB = makeDeck(ankiID: 2, name: "Deck B", in: context)
        let note = makeNote(ankiID: 1, fieldValues: ["front"], in: context)
        _ = makeCard(ankiID: 1, note: note, deck: deckA, in: context)
        _ = makeCard(ankiID: 2, note: note, deck: deckB, removed: true, in: context)
        let mediaURL = try makeMediaFile(for: note, filename: "sound.mp3", in: context)
        try context.save()

        try DeckRemover.remove(deckA, from: context)

        let notes = try fetchAll(Note.self, in: context)
        #expect(notes.isEmpty, "note has no active card anywhere and must not leak")
        #expect(!FileManager.default.fileExists(atPath: mediaURL.path))
    }

    // MARK: - DisplayConfig / HistoryEntry cascade (active-card-deck-management spec)

    @Test("removing a deck deletes its DisplayConfig and every HistoryEntry (reached and unreached)")
    func removingDeckDeletesConfigAndHistory() throws {
        let context = try makeInMemoryContext()
        let deck = makeDeck(ankiID: 1, name: "Deck A", in: context)
        let config = DisplayConfig()
        config.deck = deck
        deck.displayConfig = config
        context.insert(config)

        let note = makeNote(ankiID: 1, fieldValues: ["front"], in: context)
        let card = makeCard(ankiID: 1, note: note, deck: deck, in: context)

        let reachedEntry = HistoryEntry(sequence: 1, projectedAt: Date(), card: card, deck: deck)
        context.insert(reachedEntry)
        let unreachedEntry = HistoryEntry(sequence: 2, projectedAt: Date(), card: card, deck: deck)
        context.insert(unreachedEntry)
        deck.nextHistorySequence = 3
        deck.highestReachedSequence = 1
        deck.activeHistoryEntry = reachedEntry
        try context.save()

        try DeckRemover.remove(deck, from: context)

        let configs = try fetchAll(DisplayConfig.self, in: context)
        #expect(configs.isEmpty)
        let entries = try fetchAll(HistoryEntry.self, in: context)
        #expect(entries.isEmpty)
    }

    @Test("removing an unrelated deck that hard-deletes a shared note's card leaves the other deck's HistoryEntry row intact with card == nil")
    func removingUnrelatedDeckLeavesHistoryEntryWithNilCard() throws {
        let context = try makeInMemoryContext()
        let deckA = makeDeck(ankiID: 1, name: "Deck A", in: context)
        let deckB = makeDeck(ankiID: 2, name: "Deck B", in: context)
        let note = makeNote(ankiID: 1, fieldValues: ["front"], in: context)
        // Deck A's card is already soft-deleted (not active); Deck B's card
        // is active. Removing Deck B erases the note (ADR 0001, decision 8)
        // since none of its cards remain active outside Deck B.
        let cardA = makeCard(ankiID: 1, note: note, deck: deckA, removed: true, in: context)
        _ = makeCard(ankiID: 2, note: note, deck: deckB, in: context)

        let deckAEntry = HistoryEntry(sequence: 1, projectedAt: Date(), card: cardA, deck: deckA)
        context.insert(deckAEntry)
        deckA.highestReachedSequence = 1
        deckA.activeHistoryEntry = deckAEntry
        try context.save()

        try DeckRemover.remove(deckB, from: context)

        let entries = try fetchAll(HistoryEntry.self, in: context)
        #expect(entries.count == 1, "Deck A's HistoryEntry row must still exist")
        let survivingEntry = try #require(entries.first)
        #expect(survivingEntry.card == nil, "nullified rather than cascaded away or crashing")
    }
}
