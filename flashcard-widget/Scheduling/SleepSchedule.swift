import Foundation

struct SleepSchedule: Sendable {
    let enabled: Bool
    let startMinute: Int
    let endMinute: Int

    func contains(_ instant: Date, calendar: Calendar, timeZone: TimeZone) throws -> Bool {
        guard enabled else { return false }
        let start = try startBoundary(atOrBefore: instant, calendar: calendar, timeZone: timeZone)
        let end = try endBoundary(after: start, calendar: calendar, timeZone: timeZone)
        return instant >= start && instant < end
    }

    func addingAwakeSeconds(_ duration: TimeInterval, to date: Date, calendar: Calendar, timeZone: TimeZone) throws -> Date {
        guard duration > 0, duration.isFinite else { throw ScheduleError.malformed }
        guard enabled else { return date.addingTimeInterval(duration) }
        var cursor = date
        var remaining = duration
        while remaining > 0 {
            let recentStart = try startBoundary(atOrBefore: cursor, calendar: calendar, timeZone: timeZone)
            let recentEnd = try endBoundary(after: recentStart, calendar: calendar, timeZone: timeZone)
            if cursor >= recentStart && cursor < recentEnd {
                cursor = recentEnd
                continue
            }
            let nextStart = try startBoundary(after: cursor, calendar: calendar, timeZone: timeZone)
            let awake = nextStart.timeIntervalSince(cursor)
            if remaining < awake { return cursor.addingTimeInterval(remaining) }
            if remaining == awake { return try endBoundary(after: nextStart, calendar: calendar, timeZone: timeZone) }
            remaining -= awake
            cursor = try endBoundary(after: nextStart, calendar: calendar, timeZone: timeZone)
        }
        return cursor
    }

    func startBoundary(atOrBefore instant: Date, calendar: Calendar, timeZone: TimeZone) throws -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = boundaryComponents(startMinute)
        if matches(instant, components: components, calendar: calendar) { return instant }
        guard let result = calendar.nextDate(after: instant, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .backward) else {
            throw ScheduleError.malformed
        }
        return result
    }

    private func startBoundary(after instant: Date, calendar: Calendar, timeZone: TimeZone) throws -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone
        guard let result = calendar.nextDate(after: instant, matching: boundaryComponents(startMinute), matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward), result > instant else {
            throw ScheduleError.malformed
        }
        return result
    }

    private func endBoundary(after start: Date, calendar: Calendar, timeZone: TimeZone) throws -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = boundaryComponents(endMinute)
        guard var result = calendar.nextDate(after: start, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .last, direction: .forward), result > start else {
            throw ScheduleError.malformed
        }
        // Some Foundation versions return the first repeated wall time even
        // with `.last` when searching from before the overlap. Resolve that
        // platform discrepancy from the zone's actual offset transition.
        if let transition = timeZone.nextDaylightSavingTimeTransition(
            after: result.addingTimeInterval(-86_400)
        ), abs(transition.timeIntervalSince(result)) < 86_400 {
            let before = timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1))
            let after = timeZone.secondsFromGMT(for: transition.addingTimeInterval(1))
            let repeatedLength = before - after
            if repeatedLength > 0 {
                let alternative = result.addingTimeInterval(TimeInterval(repeatedLength))
                let fields: Set<Calendar.Component> = [.era, .year, .month, .day, .hour, .minute, .second, .nanosecond]
                if calendar.dateComponents(fields, from: alternative) == calendar.dateComponents(fields, from: result) {
                    result = alternative
                }
            }
        }
        return result
    }

    private func boundaryComponents(_ minute: Int) -> DateComponents {
        DateComponents(hour: minute / 60, minute: minute % 60, second: 0, nanosecond: 0)
    }

    private func matches(_ date: Date, components: DateComponents, calendar: Calendar) -> Bool {
        let actual = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return actual.hour == components.hour && actual.minute == components.minute && actual.second == 0 && actual.nanosecond == 0
    }
}
