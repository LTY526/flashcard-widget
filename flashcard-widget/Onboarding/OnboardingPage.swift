/// The guide's displayed copy and control state come from one testable page.
/// OnboardingView renders these values without embedding workflow actions.
struct OnboardingPage {
    let title: String
    let instructions: String
    let destination: String
    let progress: String
    let canGoBack: Bool
    let advanceLabel: String
    let showsRestart: Bool
    let dismissLabel = "Dismiss"
    let completionLabel: String?

    init(model: OnboardingModel, kind: OnboardingPresentationKind,
         observedState: OnboardingObservedState) {
        let step = model.step
        title = step.title
        instructions = step.instructions
        destination = step.destination
        progress = "Step \(model.stepIndex + 1) of \(OnboardingStep.allCases.count)"
        canGoBack = model.canGoBack
        advanceLabel = model.nextLabel
        showsRestart = kind == .manual
        completionLabel = model.stepIndex < 3
            ? (observedState.isComplete(step) ? "Complete" : "Not complete yet")
            : nil
    }
}

extension OnboardingStep {
    var destination: String {
        switch self {
        case .importDeck: "Decks → Import .apkg → Files"
        case .mapFields: "Deck → Config → Field Mapping"
        case .configureSchedule: "Deck → Config; Current for Pause/Resume"
        case .addWidget: "System Lock Screen editor → rectangular widget"
        case .selectDeck: "System Lock Screen editor → widget configuration → Deck"
        }
    }
}
