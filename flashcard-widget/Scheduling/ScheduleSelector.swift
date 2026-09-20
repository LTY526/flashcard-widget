import Foundation
import SwiftData

enum ScheduleError: Error, Equatable {
    case malformed
}

struct ScheduledCardValue: Equatable, Sendable {
    let sequence: Int
    let date: Date
    let primary: String?
    let secondary: String?
    let tertiary: String?
    let quaternary: String?
}

enum ScheduleSelection: Equatable, Sendable {
    case cards([ScheduledCardValue])
    case needsMapping
    case empty
    case paused
    case brokenSchedule
}

/// Pure provider-facing plan shared by WidgetKit production code and tests.
/// It keeps WidgetKit types out of the persistence/scheduling layer while
/// making the exact entries and reload boundary deterministic.
struct ProviderTimelinePlan: Equatable, Sendable {
    let selection: ScheduleSelection
    let reloadAfter: Date?

    static func make(deck: Deck, now: Date) -> ProviderTimelinePlan {
        let selection = ScheduleSelector.select(deck: deck, now: now)
        guard case .cards(let cards) = selection,
              let interval = deck.displayConfig?.intervalMinutes else {
            return ProviderTimelinePlan(selection: selection, reloadAfter: nil)
        }
        let reloadAfter = cards.count > 1
            ? cards.last?.date
            : now.addingTimeInterval(TimeInterval(interval * 60))
        return ProviderTimelinePlan(selection: selection, reloadAfter: reloadAfter)
    }
}

enum ScheduleSelector {
    static func select(deck: Deck, now: Date) -> ScheduleSelection {
        if deck.needsFieldMapping { return .needsMapping }
        if deck.activeCards.isEmpty { return .empty }
        if deck.isPaused { return .paused }
        guard let interval = deck.displayConfig?.intervalMinutes,
              (DisplayConfig.minimumIntervalMinutes...DisplayConfig.maximumIntervalMinutes).contains(interval)
        else { return .brokenSchedule }
        guard let queue = try? DeckScheduler.validatedUnreachedEntries(for: deck) else {
            return .brokenSchedule
        }

        let base: HistoryEntry
        if let highest = deck.highestReachedSequence {
            guard
                let pointer = deck.activeHistoryEntry,
                pointer.deck?.persistentModelID == deck.persistentModelID,
                pointer.sequence == highest,
                DeckScheduler.isRenderable(pointer)
            else { return .brokenSchedule }
            base = pointer
        } else {
            guard let first = queue.first, first.sequence == 1, first.projectedAt <= now else {
                return .brokenSchedule
            }
            base = first
        }

        var current = base
        for entry in queue where entry.sequence > base.sequence {
            let (expected, overflow) = current.sequence.addingReportingOverflow(1)
            guard !overflow, entry.sequence == expected else { return .brokenSchedule }
            if entry.projectedAt <= now {
                current = entry
            } else {
                break
            }
        }

        let candidates = [current] + queue.filter { $0.sequence > current.sequence }.prefix(4)
        var result: [ScheduledCardValue] = []
        for entry in candidates {
            guard
                let note = entry.card?.note,
                let primary = note.primaryText
            else { return .brokenSchedule }
            result.append(ScheduledCardValue(
                sequence: entry.sequence,
                date: entry === current ? now : entry.projectedAt,
                primary: primary,
                secondary: note.secondaryText,
                tertiary: note.tertiaryText,
                quaternary: note.quaternaryText
            ))
        }
        return .cards(result)
    }
}
