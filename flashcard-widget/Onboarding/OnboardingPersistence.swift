import Foundation

enum OnboardingPresentationKind {
    case automatic, manual
}

/// App preference state is deliberately separate from the pure guide model.
struct OnboardingPersistence {
    static let key = "acknowledgedOnboardingVersion"
    static let currentVersion = 1

    private let defaults: UserDefaults
    let version: Int

    init(defaults: UserDefaults = .standard, version: Int = currentVersion) {
        precondition(version > 0)
        self.defaults = defaults
        self.version = version
    }

    var acknowledgedVersion: Int { defaults.integer(forKey: Self.key) }
    var shouldPresentAutomatically: Bool { acknowledgedVersion < version }

    func handle(_ intent: OnboardingIntent, presentation: OnboardingPresentationKind) {
        switch intent {
        case .dismiss, .finish:
            if presentation == .automatic {
                defaults.set(max(acknowledgedVersion, version), forKey: Self.key)
            }
        }
    }
}
