import Foundation
import Testing
@testable import flashcard_widget

struct OnboardingAcceptanceTests {
    @Test("stable steps navigate exactly within their boundaries")
    func navigation() {
        #expect(OnboardingStep.allCases.map(\.rawValue) == [
            "importDeck", "mapFields", "configureSchedule", "addWidget", "selectDeck"
        ])
        for (index, step) in OnboardingStep.allCases.enumerated() {
            var model = OnboardingModel(at: step)
            #expect(model.stepIndex == index)
            #expect(model.canGoBack == (index > 0))
            #expect(model.nextLabel == (index == 4 ? "Finish" : "Next"))
            model.back()
            #expect(model.stepIndex == max(0, index - 1))
            model = OnboardingModel(at: step)
            if index < 4 {
                #expect(model.next() == nil)
                #expect(model.stepIndex == index + 1)
            } else {
                #expect(model.next() == .finish)
                #expect(model.stepIndex == index)
            }
            #expect(model.dismiss() == .dismiss)
            model.restart()
            #expect(model.step == .importDeck)
        }
    }

    @Test("each step teaches the required action and destination")
    func instructions() {
        let instructions = OnboardingStep.allCases.map { $0.instructions.lowercased() }
        for word in ["import", ".apkg", "files", "wait", "mapping"] { #expect(instructions[0].contains(word)) }
        for word in ["primary", "secondary", "tertiary", "quaternary", "field mapping", "config", "note type", "share"] { #expect(instructions[1].contains(word)) }
        for word in ["config", "interval", "sequential", "random", "sleep", "current", "pause", "resume"] { #expect(instructions[2].contains(word)) }
        for word in ["lock screen", "editor", "rectangular", "save", "cannot"] { #expect(instructions[3].contains(word)) }
        for word in ["lock screen", "configuration", "deck", "each widget", "quaternary", "app"] { #expect(instructions[4].contains(word)) }
    }

    @Test("checkmarks use independent observed deck predicates and never navigate")
    func checkmarks() {
        var model = OnboardingModel(at: .selectDeck)
        let ready = OnboardingDeckState(needsFieldMapping: false, isPaused: false,
            hasDisplayConfig: true, hasActivePointer: true, hasMatchingWatermark: true,
            currentEntryOwnedByDeck: true, currentEntryRenderable: true, hasPrimaryText: true)
        let state = OnboardingObservedState(decks: [ready])
        #expect(state.isComplete(.importDeck))
        #expect(state.isComplete(.mapFields))
        #expect(state.isComplete(.configureSchedule))
        #expect(!state.isComplete(.addWidget))
        #expect(!state.isComplete(.selectDeck))
        #expect(model.step == .selectDeck)

        #expect(!OnboardingObservedState(decks: []).isComplete(.importDeck))
        #expect(OnboardingObservedState(decks: [OnboardingDeckState()]).isComplete(.importDeck))
        #expect(!OnboardingObservedState(decks: [OnboardingDeckState(needsFieldMapping: true)]).isComplete(.mapFields))
        for change in [
            OnboardingDeckState(needsFieldMapping: true, isPaused: false, hasDisplayConfig: true, hasActivePointer: true, hasMatchingWatermark: true, currentEntryOwnedByDeck: true, currentEntryRenderable: true, hasPrimaryText: true),
            OnboardingDeckState(needsFieldMapping: false, isPaused: true, hasDisplayConfig: true, hasActivePointer: true, hasMatchingWatermark: true, currentEntryOwnedByDeck: true, currentEntryRenderable: true, hasPrimaryText: true),
            OnboardingDeckState(needsFieldMapping: false, isPaused: false, hasDisplayConfig: false, hasActivePointer: true, hasMatchingWatermark: true, currentEntryOwnedByDeck: true, currentEntryRenderable: true, hasPrimaryText: true),
            OnboardingDeckState(needsFieldMapping: false, isPaused: false, hasDisplayConfig: true, hasActivePointer: false, hasMatchingWatermark: true, currentEntryOwnedByDeck: true, currentEntryRenderable: true, hasPrimaryText: true),
            OnboardingDeckState(needsFieldMapping: false, isPaused: false, hasDisplayConfig: true, hasActivePointer: true, hasMatchingWatermark: false, currentEntryOwnedByDeck: true, currentEntryRenderable: true, hasPrimaryText: true),
            OnboardingDeckState(needsFieldMapping: false, isPaused: false, hasDisplayConfig: true, hasActivePointer: true, hasMatchingWatermark: true, currentEntryOwnedByDeck: false, currentEntryRenderable: true, hasPrimaryText: true),
            OnboardingDeckState(needsFieldMapping: false, isPaused: false, hasDisplayConfig: true, hasActivePointer: true, hasMatchingWatermark: true, currentEntryOwnedByDeck: true, currentEntryRenderable: false, hasPrimaryText: true),
            OnboardingDeckState(needsFieldMapping: false, isPaused: false, hasDisplayConfig: true, hasActivePointer: true, hasMatchingWatermark: true, currentEntryOwnedByDeck: true, currentEntryRenderable: true, hasPrimaryText: false)
        ] {
            #expect(!OnboardingObservedState(decks: [change]).isComplete(.configureSchedule))
        }
        model.restart()
        #expect(model.step == .importDeck)
        #expect(state.isComplete(.importDeck))
    }

    @Test("automatic acknowledgement is versioned and manual replay never writes")
    func persistence() {
        let suite = "OnboardingAcceptanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let v = OnboardingPersistence.currentVersion
        #expect(v > 0)
        let persistence = OnboardingPersistence(defaults: defaults, version: v)
        #expect(persistence.acknowledgedVersion == 0)
        #expect(persistence.shouldPresentAutomatically)
        persistence.handle(.dismiss, presentation: .automatic)
        #expect(persistence.acknowledgedVersion == v)
        #expect(!persistence.shouldPresentAutomatically)
        persistence.handle(.finish, presentation: .manual)
        #expect(persistence.acknowledgedVersion == v)
        var replay = OnboardingModel(at: .configureSchedule)
        replay.restart()
        #expect(persistence.acknowledgedVersion == v)

        defaults.set(v - 1, forKey: OnboardingPersistence.key)
        #expect(persistence.shouldPresentAutomatically)
        persistence.handle(.finish, presentation: .automatic)
        #expect(persistence.acknowledgedVersion == v)
        let raised = OnboardingPersistence(defaults: defaults, version: v + 1)
        #expect(raised.shouldPresentAutomatically)
        raised.handle(.dismiss, presentation: .automatic)
        #expect(raised.acknowledgedVersion == v + 1)
        #expect(!raised.shouldPresentAutomatically)
        persistence.handle(.finish, presentation: .automatic)
        #expect(persistence.acknowledgedVersion == v + 1)
        #expect(!persistence.shouldPresentAutomatically)
        persistence.handle(.dismiss, presentation: .manual)
        #expect(persistence.acknowledgedVersion == v + 1)
    }
}
