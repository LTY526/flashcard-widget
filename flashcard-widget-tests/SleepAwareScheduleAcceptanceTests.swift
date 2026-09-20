import Foundation
import SwiftData
import Testing
@testable import flashcard_widget

@MainActor
struct SleepAwareScheduleAcceptanceTests {
    private let utc = TimeZone(secondsFromGMT: 0)!

    @Test("sleep configuration defaults and rejects equal enabled endpoints")
    func configurationValidation() throws {
        let config = DisplayConfig()
        #expect(config.sleepEnabled == false)
        #expect(config.sleepStartMinute == 1_320)
        #expect(config.sleepEndMinute == 420)
        try config.updateSleep(enabled: true, startMinute: 1_260, endMinute: 420)
        #expect(throws: ScheduleError.self) {
            try config.updateSleep(enabled: true, startMinute: 420, endMinute: 420)
        }
        #expect(config.sleepStartMinute == 1_260)
        #expect(config.sleepEndMinute == 420)
    }

    @Test("awake addition spans sleep and exact sleep start completes at wake")
    func awakeAddition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let sleep = SleepSchedule(enabled: true, startMinute: 1_320, endMinute: 420)
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 21, minute: 50)))
        let wake = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7)))
        let twentyPast = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7, minute: 20)))
        #expect(try sleep.addingAwakeSeconds(600, to: evening, calendar: calendar, timeZone: utc) == wake)
        #expect(try sleep.addingAwakeSeconds(1_800, to: evening, calendar: calendar, timeZone: utc) == twentyPast)
        #expect(try sleep.addingAwakeSeconds(1_800, to: sleep.startBoundary(atOrBefore: wake.addingTimeInterval(-9 * 3600), calendar: calendar, timeZone: utc), calendar: calendar, timeZone: utc) == wake.addingTimeInterval(1_800))
    }

    @Test("exact and subsecond boundary membership")
    func exactBoundaryMembership() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let sleep = SleepSchedule(enabled: true, startMinute: 1_320, endMinute: 420)
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 22)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 7)))
        #expect(try sleep.contains(start, calendar: calendar, timeZone: utc))
        #expect(try sleep.contains(start.addingTimeInterval(0.5), calendar: calendar, timeZone: utc))
        #expect(!(try sleep.contains(end, calendar: calendar, timeZone: utc)))
        #expect(!(try sleep.contains(end.addingTimeInterval(0.5), calendar: calendar, timeZone: utc)))
    }

    @Test("four display roles remain independent")
    func fourRoles() {
        #expect(FieldRole.allCases.map(\.rawValue) == ["primary", "secondary", "tertiary", "quaternary"])
        let content = CardWidgetContent.resolve(primary: "P", secondary: "S", tertiary: "T", quaternary: "Q")
        #expect(content.primary == "P")
        #expect(content.secondary == "S")
        #expect(content.tertiary == "T")
        #expect(content.quaternary == "Q")

        let value = ScheduledCardValue(
            sequence: 1,
            date: .now,
            primary: "P",
            secondary: "S",
            tertiary: "T",
            quaternary: "Q"
        )
        #expect(value.primary == "P" && value.secondary == "S")
        #expect(value.tertiary == "T" && value.quaternary == "Q")
    }

    @Test("all four plain display roles preserve nil independently")
    func fourRolesPreserveNilIndependently() {
        func value(primary: String? = "P", secondary: String? = "S", tertiary: String? = "T", quaternary: String? = "Q") -> ScheduledCardValue {
            ScheduledCardValue(sequence: 1, date: .now, primary: primary, secondary: secondary, tertiary: tertiary, quaternary: quaternary)
        }

        let populated = value()
        #expect(populated.primary == "P" && populated.secondary == "S" && populated.tertiary == "T" && populated.quaternary == "Q")
        let missingPrimary = value(primary: nil)
        #expect(missingPrimary.primary == nil && missingPrimary.secondary == "S" && missingPrimary.tertiary == "T" && missingPrimary.quaternary == "Q")
        let missingSecondary = value(secondary: nil)
        #expect(missingSecondary.secondary == nil && missingSecondary.tertiary == "T" && missingSecondary.quaternary == "Q")
        let missingTertiary = value(tertiary: nil)
        #expect(missingTertiary.secondary == "S" && missingTertiary.tertiary == nil && missingTertiary.quaternary == "Q")
        let missingQuaternary = value(quaternary: nil)
        #expect(missingQuaternary.secondary == "S" && missingQuaternary.tertiary == "T" && missingQuaternary.quaternary == nil)
    }

    @Test("Schedule partitions persisted rows without mutation and paginates Past")
    func schedulePartitionAndPagination() throws {
        let (context, deck) = try fixture(interval: 30)
        let start = date(year: 2026, month: 1, day: 1, hour: 10)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        try DeckScheduler.reconcile(deck, in: context, now: start.addingTimeInterval(12 * 30 * 60))
        let before = scheduleSnapshot(deck)

        let partition = SchedulePartition(deck: deck)
        #expect(partition.isValid)
        #expect(partition.upcoming.first?.persistentModelID == deck.activeHistoryEntry?.persistentModelID)
        #expect(partition.upcoming.first?.sequence == deck.highestReachedSequence)
        #expect(partition.past.map(\.sequence) == partition.past.map(\.sequence).sorted(by: >))
        #expect(Set(partition.upcoming.map(\.persistentModelID)).isDisjoint(with: Set(partition.past.map(\.persistentModelID))))
        #expect(Set(partition.upcoming.map(\.persistentModelID) + partition.past.map(\.persistentModelID)) == Set(deck.historyEntries.map(\.persistentModelID)))
        #expect(partition.pastPage(limit: 10).count == 10)
        #expect(partition.pastPage(limit: 20).count == partition.past.count)
        #expect(scheduleSnapshot(deck) == before)
    }

    @Test("Schedule refresh derives a new partition from the newly saved graph")
    func schedulePartitionRefresh() throws {
        let (context, deck) = try fixture(interval: 30)
        let start = date(year: 2026, month: 1, day: 1, hour: 10)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let old = SchedulePartition(deck: deck)
        try DeckScheduler.next(deck, in: context, now: start.addingTimeInterval(60))
        try context.save()
        let refreshed = SchedulePartition(deck: deck)
        #expect(old.upcoming.first?.sequence == 1)
        #expect(refreshed.upcoming.first?.sequence == 2)
        #expect(refreshed.past.first?.sequence == 1)
    }

    @Test("same-day sleep is start-inclusive and end-exclusive")
    func sameDaySleepMembership() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let sleep = SleepSchedule(enabled: true, startMinute: 12 * 60, endMinute: 13 * 60)
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 12)))
        let wake = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 13)))
        #expect(try sleep.contains(noon, calendar: calendar, timeZone: utc))
        #expect(try sleep.contains(noon.addingTimeInterval(30 * 60), calendar: calendar, timeZone: utc))
        #expect(!(try sleep.contains(wake, calendar: calendar, timeZone: utc)))
    }

    @Test("subminute instants retain their exact elapsed offset")
    func subminuteWakeOffset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let sleep = SleepSchedule(enabled: true, startMinute: 1_320, endMinute: 420)
        let wake = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 3, hour: 7)))
        #expect(try sleep.addingAwakeSeconds(30, to: wake.addingTimeInterval(30), calendar: calendar, timeZone: utc) == wake.addingTimeInterval(60))
    }

    @Test("disabled sleep is exact elapsed-second addition")
    func disabledSleepAddition() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000.25)
        let result = try SleepSchedule(enabled: false, startMinute: 0, endMinute: 1)
            .addingAwakeSeconds(1_800, to: start, calendar: .current, timeZone: utc)
        #expect(result.timeIntervalSince(start) == 1_800)
    }

    @Test("spring gap and fall overlap use the required Calendar matching policies")
    func daylightSavingBoundaries() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles

        // 02:30 does not exist on this day. .nextTime moves the start to
        // 03:00, and exact exhaustion at that start moves to the 04:00 wake.
        let spring = SleepSchedule(enabled: true, startMinute: 150, endMinute: 240)
        let beforeGap = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 59)))
        let springWake = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 4)))
        #expect(try spring.addingAwakeSeconds(60, to: beforeGap, calendar: calendar, timeZone: losAngeles) == springWake)

        // The repeated 01:30 wake uses its last occurrence (standard time),
        // then another 30 awake minutes reaches 02:00 standard time.
        let fall = SleepSchedule(enabled: true, startMinute: 30, endMinute: 90)
        let fallStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30)))
        let twoAM = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 2)))
        #expect(try fall.addingAwakeSeconds(1_800, to: fallStart, calendar: calendar, timeZone: losAngeles) == twoAM)
    }

    @Test("seed during sleep is current immediately and future rows are wake-side")
    func seedDuringSleep() throws {
        let (context, deck) = try fixture(interval: 30)
        let now = date(year: 2026, month: 1, day: 1, hour: 23)
        let config = try #require(deck.displayConfig)
        try config.updateSleep(enabled: true, startMinute: 1_320, endMinute: 420)
        config.scheduleTimeZoneIdentifier = utc.identifier

        try DeckScheduler.ensureSchedule(for: deck, in: context, now: now)

        #expect(deck.activeHistoryEntry?.projectedAt == now)
        #expect(deck.highestReachedSequence == 1)
        let future = deck.historyEntries.filter { $0.sequence > 1 }.sorted { $0.sequence < $1.sequence }
        #expect(future.count == DeckScheduler.queueSize)
        #expect(future.first?.projectedAt == date(year: 2026, month: 1, day: 2, hour: 7, minute: 30))
    }

    @Test("manual Next during sleep is immediate and reschedules wake-side")
    func manualNextDuringSleep() throws {
        let (context, deck) = try fixture(interval: 30)
        let config = try #require(deck.displayConfig)
        try config.updateSleep(enabled: true, startMinute: 1_320, endMinute: 420)
        let zone = TimeZone.autoupdatingCurrent
        config.scheduleTimeZoneIdentifier = zone.identifier
        let seed = localDate(year: 2026, month: 1, day: 1, hour: 21, timeZone: zone)
        let nextAt = localDate(year: 2026, month: 1, day: 1, hour: 23, timeZone: zone)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: seed)

        try DeckScheduler.next(deck, in: context, now: nextAt)

        // Sequence 2 became due before bedtime; Next reconciles it first and
        // then advances exactly once to sequence 3.
        #expect(deck.activeHistoryEntry?.sequence == 3)
        #expect(deck.activeHistoryEntry?.projectedAt == nextAt)
        let successor = try #require(deck.historyEntries.first { $0.sequence == 4 })
        #expect(successor.projectedAt == localDate(year: 2026, month: 1, day: 2, hour: 7, minute: 30, timeZone: zone))
    }

    @Test("resume during sleep creates a current row now and wake-side successors")
    func resumeDuringSleep() throws {
        let (context, deck) = try fixture(interval: 30)
        let config = try #require(deck.displayConfig)
        try config.updateSleep(enabled: true, startMinute: 1_320, endMinute: 420)
        config.scheduleTimeZoneIdentifier = utc.identifier
        let seed = date(year: 2026, month: 1, day: 1, hour: 21)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: seed)
        try DeckScheduler.setPaused(true, deck: deck, in: context, now: seed)

        let resumedAt = date(year: 2026, month: 1, day: 1, hour: 23)
        try DeckScheduler.setPaused(false, deck: deck, in: context, now: resumedAt)

        #expect(deck.activeHistoryEntry?.sequence == 2)
        #expect(deck.activeHistoryEntry?.projectedAt == resumedAt)
        let future = deck.historyEntries.filter { $0.sequence > 2 }.sorted { $0.sequence < $1.sequence }
        #expect(future.count == DeckScheduler.queueSize)
        #expect(future.first?.projectedAt == date(year: 2026, month: 1, day: 2, hour: 7, minute: 30))
        let sleep = SleepSchedule(enabled: true, startMinute: 1_320, endMinute: 420)
        let everyFutureDateIsAwake = try future.allSatisfy {
            !(try sleep.contains($0.projectedAt, calendar: Calendar(identifier: .gregorian), timeZone: utc))
        }
        #expect(everyFutureDateIsAwake)
    }

    @Test("future rebuild preserves current and anchors a full interval at edit time")
    func rebuildFutureAtEditTime() throws {
        let (context, deck) = try fixture(interval: 30)
        let seed = date(year: 2026, month: 1, day: 1, hour: 10)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: seed)
        let currentID = try #require(deck.activeHistoryEntry?.persistentModelID)
        let edit = seed.addingTimeInterval(300)
        try DeckScheduler.rebuildFuture(for: deck, in: context, now: edit, timeZone: utc)
        #expect(deck.activeHistoryEntry?.persistentModelID == currentID)
        let future = deck.historyEntries.filter { $0.sequence > 1 }.sorted { $0.sequence < $1.sequence }
        #expect(future.count == DeckScheduler.queueSize)
        #expect(future.first?.projectedAt == edit.addingTimeInterval(1_800))
    }

    @Test("activation planning is atomic and idempotent")
    func activationBatchPlanning() throws {
        let (context, deck) = try fixture(interval: 30)
        let start = date(year: 2026, month: 1, day: 1, hour: 10)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let originalSequence = deck.highestReachedSequence
        let originalCount = deck.historyEntries.count

        let brokenDeck = Deck(ankiDeckID: 2, name: "Broken")
        let brokenConfig = DisplayConfig(intervalMinutes: 30)
        brokenConfig.intervalMinutes = 0
        brokenConfig.deck = brokenDeck
        brokenDeck.displayConfig = brokenConfig
        let note = Note(ankiNoteID: 99, fieldValues: ["Broken"], noteType: nil)
        let card = Card(ankiCardID: 99, ordinal: 0, note: note, deck: brokenDeck)
        context.insert(brokenDeck)
        context.insert(note)
        context.insert(card)

        #expect(throws: ScheduleError.self) {
            try DeckScheduler.planReconciliation(
                for: [deck, brokenDeck],
                now: start.addingTimeInterval(3_600),
                timeZone: utc
            )
        }
        #expect(deck.highestReachedSequence == originalSequence)
        #expect(deck.historyEntries.count == originalCount)

        context.delete(brokenDeck)
        let now = start.addingTimeInterval(3_600)
        let first = try DeckScheduler.planReconciliation(for: [deck], now: now, timeZone: utc)
        DeckScheduler.apply(first, in: context)
        let afterFirstSequence = deck.highestReachedSequence
        let afterFirstCount = deck.historyEntries.count
        let second = try DeckScheduler.planReconciliation(for: [deck], now: now, timeZone: utc)
        let secondChangesAnything = second.map(\.changesProgress).contains(true)
        #expect(!secondChangesAnything)
        DeckScheduler.apply(second, in: context)
        #expect(deck.highestReachedSequence == afterFirstSequence)
        #expect(deck.historyEntries.count == afterFirstCount)
    }

    @Test("activation save failure rolls back for a newly opened context")
    func activationSaveFailureRollsBackPersistedGraph() throws {
        enum InjectedFailure: Error { case save }
        let (context, deck) = try fixture(interval: 30)
        let start = date(year: 2026, month: 1, day: 1, hour: 10)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        try context.save()
        let container = context.container
        let beforeCurrent = deck.activeHistoryEntry?.sequence
        let beforeWatermark = deck.highestReachedSequence
        let beforeRows = deck.historyEntries.sorted { $0.sequence < $1.sequence }.map { ($0.sequence, $0.projectedAt) }

        #expect(throws: InjectedFailure.save) {
            try DeckScheduler.reconcileOnActivation(
                in: container,
                now: start.addingTimeInterval(3 * 30 * 60),
                timeZone: utc,
                save: { _ in throw InjectedFailure.save }
            )
        }

        let verificationContext = ModelContext(container)
        let persistedDeck = try #require(try verificationContext.fetch(FetchDescriptor<Deck>()).first)
        let persistedRows = persistedDeck.historyEntries.sorted { $0.sequence < $1.sequence }.map { ($0.sequence, $0.projectedAt) }
        #expect(persistedDeck.activeHistoryEntry?.sequence == beforeCurrent)
        #expect(persistedDeck.highestReachedSequence == beforeWatermark)
        #expect(persistedRows.elementsEqual(beforeRows, by: ==))
    }

    @Test("travel discards old-zone future dates before they can advance progress")
    func timeZoneTravelRebuildsBeforeReconcile() throws {
        let (context, deck) = try fixture(interval: 30)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let config = try #require(deck.displayConfig)
        try config.updateSleep(enabled: true, startMinute: 1_320, endMinute: 420)
        config.scheduleTimeZoneIdentifier = "Pacific/Honolulu"
        for entry in deck.historyEntries where entry.sequence > 1 {
            entry.projectedAt = start.addingTimeInterval(-60)
        }

        try DeckScheduler.reconcile(deck, in: context, now: start)

        #expect(deck.highestReachedSequence == 1)
        #expect(config.scheduleTimeZoneIdentifier == TimeZone.autoupdatingCurrent.identifier)
        let future = deck.historyEntries.filter { $0.sequence > 1 }
        #expect(future.count == DeckScheduler.queueSize)
        #expect(future.allSatisfy { $0.projectedAt > start })
    }

    @Test("disabled sleep time-zone change preserves every absolute queue date")
    func disabledSleepTravelPreservesDates() throws {
        let (context, deck) = try fixture(interval: 30)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let config = try #require(deck.displayConfig)
        config.sleepEnabled = false
        config.scheduleTimeZoneIdentifier = "Pacific/Honolulu"
        let before = deck.historyEntries.sorted { $0.sequence < $1.sequence }.map(\.projectedAt)

        let zone = try #require(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let plans = try DeckScheduler.planReconciliation(for: [deck], now: start, timeZone: zone)
        DeckScheduler.apply(plans, in: context)

        #expect(config.scheduleTimeZoneIdentifier == zone.identifier)
        #expect(deck.historyEntries.sorted { $0.sequence < $1.sequence }.map(\.projectedAt) == before)
    }

    @Test("provider timeline construction keeps the card visible until its shifted wake-side date")
    func providerTimelineSleepSpanningVisibility() throws {
        let (context, deck) = try fixture(interval: 30)
        let config = try #require(deck.displayConfig)
        try config.updateSleep(enabled: true, startMinute: 0, endMinute: 480)
        config.scheduleTimeZoneIdentifier = utc.identifier
        let start = date(year: 2026, month: 1, day: 1, hour: 23, minute: 50)
        try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
        let due = date(year: 2026, month: 1, day: 2, hour: 8, minute: 20)

        let beforePlan = ProviderTimelinePlan.make(deck: deck, now: due.addingTimeInterval(-1))
        let atDuePlan = ProviderTimelinePlan.make(deck: deck, now: due)
        guard case .cards(let beforeWake) = beforePlan.selection,
              case .cards(let atDue) = atDuePlan.selection else {
            Issue.record("Expected deterministic provider timeline plans")
            return
        }
        #expect(beforeWake.first?.sequence == 1)
        #expect(atDue.first?.sequence == 2)
        #expect(atDue.map(\.sequence) == [2, 3, 4, 5, 6])
        #expect(beforePlan.reloadAfter == beforeWake.last?.date)
        #expect(atDuePlan.reloadAfter == atDue.last?.date)
    }

    @Test("activation remains blocked after failure and unblocks only after success")
    func activationGateRequiresSuccessfulCommit() {
        var gate = ActivationGate()
        #expect(gate.blocksContent)
        #expect(gate.isReconciling)

        gate.reconciliationFailed()
        #expect(gate.blocksContent)
        #expect(!gate.isReconciling)

        gate.beginReconciliation()
        #expect(gate.blocksContent)
        #expect(gate.isReconciling)

        gate.reconciliationSucceeded()
        #expect(!gate.blocksContent)
        #expect(!gate.isReconciling)
    }

    @Test("visible schedule reloads committed data from a separate context")
    func visibleScheduleReloadsSeparateContextCommit() throws {
        let (visibleContext, visibleDeck) = try fixture(interval: 30)
        let container = visibleContext.container
        let deckID = visibleDeck.persistentModelID
        let start = date(year: 2026, month: 1, day: 1, hour: 10)
        try DeckScheduler.ensureSchedule(for: visibleDeck, in: visibleContext, now: start)
        try visibleContext.save()

        let before = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(before.upcoming.first?.sequence == 1)
        #expect(before.past.isEmpty)

        let writer = ModelContext(container)
        let writerDeck = try #require(writer.model(for: deckID) as? Deck)
        try DeckScheduler.reconcile(writerDeck, in: writer, now: start.addingTimeInterval(2 * 30 * 60))
        try writer.save()

        // The already-registered model remains the exact object the visible
        // navigation stack holds. The schedule data source must nevertheless
        // observe the separately committed graph.
        #expect(visibleDeck.highestReachedSequence == 1)
        let refreshed = try ScheduleSnapshot.load(deckID: deckID, from: container)
        #expect(refreshed.upcoming.first?.sequence == 3)
        #expect(refreshed.upcoming.first?.isCurrent == true)
        #expect(refreshed.past.map(\.sequence) == [2, 1])
        #expect(refreshed.upcoming.dropFirst().first?.sequence == 4)
    }

    @Test("app reconciliation and provider selection agree for zero, one, and several due rows")
    func appProviderParity() throws {
        for dueCount in [0, 1, 4] {
            let (context, deck) = try fixture(interval: 30)
            let start = date(year: 2026, month: 1, day: 1, hour: 10)
            try DeckScheduler.ensureSchedule(for: deck, in: context, now: start)
            let now = start.addingTimeInterval(TimeInterval(dueCount * 30 * 60))
            guard case .cards(let selected) = ScheduleSelector.select(deck: deck, now: now) else {
                Issue.record("Expected provider selection for due count \(dueCount)")
                continue
            }
            try DeckScheduler.reconcile(deck, in: context, now: now)
            #expect(selected.first?.sequence == deck.activeHistoryEntry?.sequence)
            #expect(deck.highestReachedSequence == dueCount + 1)
        }
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        localDate(year: year, month: month, day: day, hour: hour, minute: minute, timeZone: utc)
    }

    private func localDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func fixture(interval: Int) throws -> (ModelContext, Deck) {
        let schema = SharedModelContainer.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let deck = Deck(ankiDeckID: 1, name: "Deck")
        let type = NoteType(ankiNoteTypeID: 1, name: "Basic")
        let field = NoteTypeField(name: "Front", ordinal: 0, role: .primary)
        field.noteType = type
        for id in 1...3 {
            let note = Note(ankiNoteID: Int64(id), fieldValues: ["Card \(id)"], noteType: type)
            context.insert(note)
            context.insert(Card(ankiCardID: Int64(id), ordinal: 0, note: note, deck: deck))
        }
        let config = DisplayConfig(intervalMinutes: interval)
        config.deck = deck
        deck.displayConfig = config
        context.insert(deck)
        context.insert(type)
        context.insert(field)
        context.insert(config)
        try context.save()
        return (context, deck)
    }

    private func scheduleSnapshot(_ deck: Deck) -> [String] {
        deck.historyEntries.sorted { $0.sequence < $1.sequence }.map {
            "\($0.sequence)|\($0.projectedAt.timeIntervalSinceReferenceDate)|\($0.persistentModelID)"
        } + ["current=\(String(describing: deck.activeHistoryEntry?.persistentModelID))", "watermark=\(String(describing: deck.highestReachedSequence))"]
    }
}
