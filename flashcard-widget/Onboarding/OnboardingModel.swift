import Foundation

enum OnboardingStep: String, CaseIterable, Identifiable {
    case importDeck, mapFields, configureSchedule, addWidget, selectDeck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importDeck: "Import a deck"
        case .mapFields: "Map fields"
        case .configureSchedule: "Configure the schedule"
        case .addWidget: "Add the widget"
        case .selectDeck: "Select a deck"
        }
    }

    var instructions: String {
        switch self {
        case .importDeck:
            "On the root deck list, tap Import .apkg. Choose an Anki .apkg file from Files, wait for the import to complete, and follow any Field Mapping prompt."
        case .mapFields:
            "Choose a primary field and, if useful, secondary, tertiary, and quaternary roles. To change them later, open a deck's Config mode and tap Field Mapping. Decks that share a note type also share its mapping."
        case .configureSchedule:
            "Open the deck's Config mode to review the interval, sequential or random order, and optional sleep times. Pause or resume the deck in Current mode."
        case .addWidget:
            "Open the system Lock Screen editor, add this app's rectangular widget, and save the customized Lock Screen. The app cannot install the widget for you."
        case .selectDeck:
            "While editing the Lock Screen, open that widget's configuration and select its Deck. Each widget has its own deck selection. Quaternary content remains in the app only."
        }
    }
}

enum OnboardingIntent {
    case dismiss, finish
}

/// Navigation has no knowledge of storage, deck objects, or presentation.
struct OnboardingModel {
    private(set) var stepIndex: Int

    init(at step: OnboardingStep = .importDeck) {
        stepIndex = OnboardingStep.allCases.firstIndex(of: step)!
    }

    var step: OnboardingStep { OnboardingStep.allCases[stepIndex] }
    var canGoBack: Bool { stepIndex > 0 }
    var nextLabel: String { stepIndex == OnboardingStep.allCases.count - 1 ? "Finish" : "Next" }

    mutating func back() { stepIndex = max(0, stepIndex - 1) }

    mutating func next() -> OnboardingIntent? {
        if stepIndex == OnboardingStep.allCases.count - 1 { return finish() }
        stepIndex += 1
        return nil
    }

    mutating func restart() { stepIndex = 0 }
    func dismiss() -> OnboardingIntent { .dismiss }
    func finish() -> OnboardingIntent { .finish }
}

struct OnboardingDeckState {
    var needsFieldMapping = false
    var isPaused = false
    var hasDisplayConfig = false
    var hasActivePointer = false
    var hasMatchingWatermark = false
    var currentEntryOwnedByDeck = false
    var currentEntryRenderable = false
    var hasPrimaryText = false
}

struct OnboardingObservedState {
    var decks: [OnboardingDeckState]

    func isComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .importDeck: !decks.isEmpty
        case .mapFields: decks.contains { !$0.needsFieldMapping }
        case .configureSchedule:
            decks.contains {
                !$0.needsFieldMapping && !$0.isPaused && $0.hasDisplayConfig &&
                $0.hasActivePointer && $0.hasMatchingWatermark &&
                $0.currentEntryOwnedByDeck && $0.currentEntryRenderable && $0.hasPrimaryText
            }
        case .addWidget, .selectDeck: false
        }
    }
}
