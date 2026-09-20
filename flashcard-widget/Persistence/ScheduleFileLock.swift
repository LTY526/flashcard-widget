import Darwin
import Foundation

enum MutationLockError: Error, Equatable {
    case timedOut
    case unavailable
}

struct ScheduleFileLock: Sendable {
    enum Mode: Sendable {
        case shared
        case exclusive

        fileprivate var operation: Int32 {
            switch self {
            case .shared: LOCK_SH | LOCK_NB
            case .exclusive: LOCK_EX | LOCK_NB
            }
        }
    }

    let fileURL: URL
    var timeout: Duration = .seconds(2)
    var pollInterval: Duration = .milliseconds(50)

    func withLock<T: Sendable>(
        mode: Mode,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let descriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw MutationLockError.unavailable }
        defer { close(descriptor) }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while flock(descriptor, mode.operation) != 0 {
            try Task.checkCancellation()
            guard clock.now < deadline else { throw MutationLockError.timedOut }
            try await Task.sleep(for: pollInterval)
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        return try await operation()
    }

    /// Short synchronous mutations initiated by a control already running on
    /// the main actor use the same cross-process lock as async reconciliation.
    /// Keeping this primitive here prevents any schedule writer from bypassing
    /// the app/widget coordination contract.
    func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw MutationLockError.unavailable }
        defer { close(descriptor) }

        let deadline = Date().addingTimeInterval(2)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard Date() < deadline else { throw MutationLockError.timedOut }
            usleep(50_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    static func shared() throws -> ScheduleFileLock {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedModelContainer.appGroupIdentifier
        ) else {
            throw SharedStoreError.groupContainerUnavailable
        }
        return ScheduleFileLock(fileURL: directory.appendingPathComponent(".schedule-mutation.lock"))
    }
}
