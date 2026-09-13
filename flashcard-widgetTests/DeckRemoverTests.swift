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
}
