/// Tracks an automatic introduction until it is shown, including while a
/// manual replay or another modal is on screen. Storage remains elsewhere.
struct OnboardingPresentationQueue {
    private(set) var pendingAutomatic = false
    private(set) var active: OnboardingPresentationKind?

    mutating func activationSucceeded(shouldPresentAutomatically: Bool) {
        if shouldPresentAutomatically { pendingAutomatic = true }
    }

    mutating func beginManual() -> Bool {
        guard active == nil else { return false }
        active = .manual
        return true
    }

    mutating func beginAutomaticIfReady(_ otherModalsClosed: Bool) -> Bool {
        guard pendingAutomatic, active == nil, otherModalsClosed else { return false }
        pendingAutomatic = false
        active = .automatic
        return true
    }

    mutating func closed(_ kind: OnboardingPresentationKind) {
        guard active == kind else { return }
        active = nil
        if kind == .automatic { pendingAutomatic = false }
    }
}
