import SwiftData
import SwiftUI

struct OnboardingSession: Identifiable {
    let id = UUID()
    let kind: OnboardingPresentationKind
    let initialStep: OnboardingStep
}

/// A live SwiftData query supplies plain values to the instructional view.
/// Query changes while the sheet is open therefore refresh the checkmarks.
struct OnboardingObservedDeckSource: View {
    @Query(sort: \Deck.name) private var decks: [Deck]
    let session: OnboardingSession
    let onIntent: (OnboardingIntent) -> Void

    var body: some View {
        OnboardingView(kind: session.kind, initialStep: session.initialStep,
                       observedState: OnboardingObservedState(decks: decks),
                       onIntent: onIntent)
    }
}

struct OnboardingView: View {
    @State private var model: OnboardingModel
    let observedState: OnboardingObservedState
    let kind: OnboardingPresentationKind
    let onIntent: (OnboardingIntent) -> Void

    init(kind: OnboardingPresentationKind, initialStep: OnboardingStep = .importDeck,
         observedState: OnboardingObservedState,
         onIntent: @escaping (OnboardingIntent) -> Void) {
        self.kind = kind
        self.observedState = observedState
        self.onIntent = onIntent
        _model = State(initialValue: OnboardingModel(at: initialStep))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Step \(model.stepIndex + 1) of \(OnboardingStep.allCases.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(model.step.title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text(model.step.instructions)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.stepIndex < 3 {
                        Label(
                            observedState.isComplete(model.step) ? "Complete" : "Not complete yet",
                            systemImage: observedState.isComplete(model.step) ? "checkmark.circle.fill" : "circle"
                        )
                        .accessibilityLabel("\(model.step.title): \(observedState.isComplete(model.step) ? "complete" : "not complete yet")")
                    }

                    Text("You can close this guide to use the app, then reopen Getting Started to check your progress.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(OnboardingStep.allCases) { step in
                        HStack {
                            Text(step.title)
                            Spacer()
                            if OnboardingStep.allCases.firstIndex(of: step)! < 3 && observedState.isComplete(step) {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }

                    HStack {
                        Button("Back") { model.back() }
                            .disabled(!model.canGoBack)
                        Spacer()
                        Button(model.nextLabel) {
                            if let intent = model.next() { onIntent(intent) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Getting Started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if kind == .manual {
                        Button("Restart") { model.restart() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dismiss") { onIntent(model.dismiss()) }
                }
            }
        }
    }
}

#Preview("Select deck") {
    OnboardingView(kind: .manual, initialStep: .selectDeck,
                   observedState: OnboardingObservedState(decks: [] as [OnboardingDeckState]), onIntent: { _ in })
}
