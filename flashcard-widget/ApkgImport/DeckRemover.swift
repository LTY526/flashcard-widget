//
//  DeckRemover.swift
//  flashcard-widget
//
//  User-initiated deck removal is a hard delete, unlike the soft-delete
//  reconciliation ApkgImporter performs on re-import (ADR 0001, decision 6
//  covers automatic re-import reconciliation only; decision 8 is the
//  deliberate exception this file implements). A note is only erased if
//  it has no *active* card left outside the deck being removed -- a note
//  whose only other card is itself soft-deleted (e.g. removed by a prior
//  re-import) is not "still in active use elsewhere" and must not block
//  cleanup, or its row and media would leak forever. Media files on disk
//  are removed alongside any note that's fully erased.
//

import Foundation
import SwiftData

enum DeckRemover {
    static func remove(_ deck: Deck, from modelContext: ModelContext) throws {
        let deckCardIDs = Set(deck.cards.map(\.persistentModelID))

        var noteIDsToDelete: Set<PersistentIdentifier> = []
        for card in deck.cards {
            guard let note = card.note else { continue }
            let hasActiveCardElsewhere = note.cards.contains { otherCard in
                otherCard.isActive && !deckCardIDs.contains(otherCard.persistentModelID)
            }
            if !hasActiveCardElsewhere {
                noteIDsToDelete.insert(note.persistentModelID)
            }
        }

        for noteID in noteIDsToDelete {
            guard let note = modelContext.model(for: noteID) as? Note else { continue }
            deleteMediaFiles(for: note)
            modelContext.delete(note)
        }

        modelContext.delete(deck)
        try modelContext.save()
    }

    private static func deleteMediaFiles(for note: Note) {
        for mediaItem in note.mediaItems {
            let url = MediaImporter.storageDirectory().appendingPathComponent(mediaItem.relativeStoragePath)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
