//
//  DisplayConfig.swift
//  flashcard-widget
//
//  Exactly one `DisplayConfig` exists per `Deck` (ADR 0002, decision 3) --
//  there is no "add another config" or "switch which one is in use"
//  concept, so this is a one-to-one relationship, not a list the user
//  manages. `order` and `intervalMinutes` have real scheduling effect via
//  `DeckScheduler`; sleep settings affect projected dates.
//

import Foundation
import SwiftData

@Model
final class DisplayConfig {
    /// Floor enforced by the edit UI -- `intervalMinutes` is advisory
    /// scheduling spacing, not a guaranteed exact interval, but it still
    /// isn't allowed to be so small it stops meaning anything.
    static let minimumIntervalMinutes = 15
    static let maximumIntervalMinutes = 1440
    static let defaultIntervalMinutes = 30

    var orderRawValue: String = DisplayOrder.sequential.rawValue
    var intervalMinutes: Int = DisplayConfig.defaultIntervalMinutes
    var sleepEnabled: Bool = false
    var sleepStartMinute: Int = 1_320
    var sleepEndMinute: Int = 420
    var scheduleTimeZoneIdentifier: String?

    var deck: Deck?

    init(
        order: DisplayOrder = .sequential,
        intervalMinutes: Int = DisplayConfig.defaultIntervalMinutes
    ) {
        self.orderRawValue = order.rawValue
        self.intervalMinutes = DisplayConfig.clampedIntervalMinutes(intervalMinutes)
    }

    var order: DisplayOrder {
        get { DisplayOrder(rawValue: orderRawValue) ?? .sequential }
        set { orderRawValue = newValue.rawValue }
    }

    /// Clamps a candidate `intervalMinutes` value to the 15-minute floor.
    /// Shared by `init` and the edit UI so the floor is enforced in exactly
    /// one place.
    static func clampedIntervalMinutes(_ candidate: Int) -> Int {
        min(max(candidate, minimumIntervalMinutes), maximumIntervalMinutes)
    }

    /// Applies a new `intervalMinutes`, clamped to the floor. Editing this
    /// only changes the spacing used for entries generated *after* the
    /// edit -- it never retroactively rewrites `projectedAt` on entries
    /// already in the queue (ADR 0002, decision 3).
    func updateIntervalMinutes(_ candidate: Int) {
        intervalMinutes = DisplayConfig.clampedIntervalMinutes(candidate)
    }

    func updateSleep(enabled: Bool, startMinute: Int, endMinute: Int) throws {
        guard (0...1_439).contains(startMinute), (0...1_439).contains(endMinute),
              !enabled || startMinute != endMinute else { throw ScheduleError.malformed }
        sleepEnabled = enabled
        sleepStartMinute = startMinute
        sleepEndMinute = endMinute
    }

    func validateSleep() throws {
        guard (0...1_439).contains(sleepStartMinute),
              (0...1_439).contains(sleepEndMinute),
              !sleepEnabled || sleepStartMinute != sleepEndMinute else {
            throw ScheduleError.malformed
        }
    }
}
