import SwiftData

extension OnboardingObservedState {
    /// Read the saved app graph afresh whenever the guide is shown or refreshed.
    init(decks: [Deck]) {
        self.decks = decks.map { deck in
            let pointer = deck.activeHistoryEntry
            return OnboardingDeckState(
                needsFieldMapping: deck.needsFieldMapping,
                isPaused: deck.isPaused,
                hasDisplayConfig: deck.displayConfig != nil,
                hasActivePointer: pointer != nil,
                hasMatchingWatermark: pointer != nil && deck.highestReachedSequence != nil && pointer?.sequence == deck.highestReachedSequence,
                currentEntryOwnedByDeck: pointer?.deck?.persistentModelID == deck.persistentModelID,
                currentEntryRenderable: pointer.map(DeckScheduler.isRenderable) ?? false,
                hasPrimaryText: pointer?.card?.note?.primaryText != nil
            )
        }
    }
}
