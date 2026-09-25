//
//  DeckScheduler.swift
//  flashcard-widget
//
//  Owns the queue rules superseded by ADR 0003: per-deck queue
//  top-up, time reconciliation, Next, the two reset triggers (order change, soft-delete
//  reconciliation), and history pagination. All entry points are no-ops
//  (not crashes) on a deck with zero active cards, and every
//  regeneration path is gated by `Deck.isPaused` -- except the *discard*
//  half of a reset, which always runs.
//
//  `sequence` is strict identity/order. `projectedAt` is compared with an
//  injected clock only to derive the contiguous due prefix.
//

import Foundation
import SwiftData

enum ScheduleQueryTrace {
    enum Kind: Equatable {
        case past(watermark: Int, before: Int?)
        case unreached
        case current(sequence: Int)
    }
    struct Event {
        let kind: Kind
        let fetchLimit: Int
        let returnedCount: Int
    }
    static var observeFetch: ((Event) -> Void)?
    /// Test seam for a failed persistence read. The normal path still executes
    /// ModelContext.fetch and records only completed fetches below.
    static var failBeforeFetch: ((Kind) throws -> Void)?

    static func fetch(_ descriptor: FetchDescriptor<HistoryEntry>,
                      in context: ModelContext, kind: Kind) throws -> [HistoryEntry] {
        try failBeforeFetch?(kind)
        let rows = try context.fetch(descriptor)
        observeFetch?(Event(kind: kind, fetchLimit: descriptor.fetchLimit ?? .max,
                            returnedCount: rows.count))
        return rows
    }
}

enum DeckScheduler {
    /// A non-paused deck with at least one active card always has at
    /// least this many `HistoryEntry` rows queued (generated but not yet
    /// reached).
    static let queueSize = 100

    /// Both Schedule subsections reveal rows in small, consistent pages.
    static let historyPageSize = 20

    /// Runs the complete foreground transaction in a disposable context.
    /// Callers acquire the cross-process exclusive lock before invoking this.
    /// The injectable save operation exists so persistence-failure rollback can
    /// be verified without reusing the failed context.
    static func reconcileOnActivation(
        in container: ModelContainer,
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Bool {
        let context = ModelContext(container)
        do {
            let decks = try context.fetch(FetchDescriptor<Deck>()).filter { !$0.isPaused }
            let plans = try planReconciliation(for: decks, in: context, now: now, timeZone: timeZone)
            let changed = plans.contains(where: \.changesProgress)
            apply(plans, in: context)
            if changed { try save(context) }
            return changed
        } catch {
            context.rollback()
            throw error
        }
    }

    struct ReconciliationPlan {
        fileprivate struct NewEntry {
            let sequence: Int
            let projectedAt: Date
            let card: Card
        }

        fileprivate let deck: Deck
        fileprivate let entriesToDelete: [HistoryEntry]
        fileprivate let entriesToInsert: [NewEntry]
        fileprivate let existingCurrent: HistoryEntry?
        fileprivate let insertedCurrentIndex: Int?
        fileprivate let highestReachedSequence: Int?
        fileprivate let nextHistorySequence: Int
        fileprivate let timeZoneIdentifier: String?

        var changesProgress: Bool {
            !entriesToDelete.isEmpty || !entriesToInsert.isEmpty ||
                deck.highestReachedSequence != highestReachedSequence ||
                deck.activeHistoryEntry !== existingCurrent ||
                deck.displayConfig?.scheduleTimeZoneIdentifier != timeZoneIdentifier
        }
    }

    /// Computes a complete activation batch without changing a model. If any
    /// deck is malformed, no plan is returned and every model remains intact.
    static func planReconciliation(
        for decks: [Deck],
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> [ReconciliationPlan] {
        try decks.map { try reconciliationPlan(for: $0, in: try context(for: $0), now: now, timeZone: timeZone) }
    }

    static func planReconciliation(
        for decks: [Deck], in context: ModelContext,
        now: Date, timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> [ReconciliationPlan] {
        try decks.map { try reconciliationPlan(for: $0, in: context, now: now, timeZone: timeZone) }
    }

    /// Applies only prevalidated values. This phase cannot discover a schedule
    /// error; persistence errors are handled by the caller's single save and
    /// rollback.
    static func apply(_ plans: [ReconciliationPlan], in modelContext: ModelContext) {
        for plan in plans where plan.changesProgress {
            for entry in plan.entriesToDelete {
                entry.deck = nil
                modelContext.delete(entry)
            }

            var inserted: [HistoryEntry] = []
            for value in plan.entriesToInsert {
                let entry = HistoryEntry(
                    sequence: value.sequence,
                    projectedAt: value.projectedAt,
                    card: value.card,
                    deck: plan.deck
                )
                modelContext.insert(entry)
                inserted.append(entry)
            }
            plan.deck.highestReachedSequence = plan.highestReachedSequence
            plan.deck.activeHistoryEntry = plan.insertedCurrentIndex.map { inserted[$0] } ?? plan.existingCurrent
            plan.deck.nextHistorySequence = plan.nextHistorySequence
            plan.deck.displayConfig?.scheduleTimeZoneIdentifier = plan.timeZoneIdentifier
        }
    }

    private static func reconciliationPlan(
        for deck: Deck,
        in context: ModelContext,
        now: Date,
        timeZone: TimeZone
    ) throws -> ReconciliationPlan {
        guard !deck.isPaused, !deck.activeCards.isEmpty else {
            return ReconciliationPlan(
                deck: deck, entriesToDelete: [], entriesToInsert: [],
                existingCurrent: deck.activeHistoryEntry, insertedCurrentIndex: nil,
                highestReachedSequence: deck.highestReachedSequence,
                nextHistorySequence: deck.nextHistorySequence,
                timeZoneIdentifier: deck.displayConfig?.scheduleTimeZoneIdentifier
            )
        }
        let interval = try validatedIntervalSeconds(for: deck)
        try deck.displayConfig?.validateSleep()
        let configuredZone = deck.displayConfig?.scheduleTimeZoneIdentifier
        let zoneChanged = configuredZone != timeZone.identifier
        let rebuildForZone = zoneChanged && (deck.displayConfig?.sleepEnabled == true)
        let validated = try validatedUnreachedEntries(for: deck, in: context)

        let deletes: [HistoryEntry] = rebuildForZone ? validated : []
        var retainedFuture = rebuildForZone ? [] : validated
        var current = deck.activeHistoryEntry
        var highest = deck.highestReachedSequence
        if !rebuildForZone, let effective = retainedFuture.prefix(while: { $0.projectedAt <= now }).last {
            current = effective
            highest = effective.sequence
            retainedFuture.removeAll { $0.sequence <= effective.sequence }
        }

        var additions: [ReconciliationPlan.NewEntry] = []
        var insertedCurrentIndex: Int?
        var nextSequence: Int
        if rebuildForZone {
            let increment = (highest ?? 0).addingReportingOverflow(1)
            guard !increment.overflow else { throw ScheduleError.malformed }
            nextSequence = increment.partialValue
        } else {
            nextSequence = deck.nextHistorySequence
        }
        var referenceCard = retainedFuture.last?.card ?? current?.card
        var referenceDate = retainedFuture.last?.projectedAt ?? current?.projectedAt

        if current == nil, highest == nil, validated.isEmpty {
            guard let firstCard = initialCard(for: deck) else { throw ScheduleError.malformed }
            let sequence = nextSequence
            let increment = sequence.addingReportingOverflow(1)
            guard !increment.overflow else { throw ScheduleError.malformed }
            additions.append(.init(sequence: sequence, projectedAt: now, card: firstCard))
            insertedCurrentIndex = 0
            highest = sequence
            nextSequence = increment.partialValue
            referenceCard = firstCard
            referenceDate = now
        }

        while retainedFuture.count + additions.count - (insertedCurrentIndex == nil ? 0 : 1) < queueSize {
            guard let anchorDate = referenceDate else { throw ScheduleError.malformed }
            let card = plannedNextCard(after: referenceCard, for: deck)
            let date = try scheduledDate(
                after: (rebuildForZone && retainedFuture.isEmpty && additions.isEmpty) ? now : anchorDate,
                seconds: interval,
                deck: deck,
                timeZone: timeZone
            )
            let increment = nextSequence.addingReportingOverflow(1)
            guard !increment.overflow else { throw ScheduleError.malformed }
            additions.append(.init(sequence: nextSequence, projectedAt: date, card: card))
            nextSequence = increment.partialValue
            referenceCard = card
            referenceDate = date
        }

        return ReconciliationPlan(
            deck: deck,
            entriesToDelete: deletes,
            entriesToInsert: additions,
            existingCurrent: current,
            insertedCurrentIndex: insertedCurrentIndex,
            highestReachedSequence: highest,
            nextHistorySequence: nextSequence,
            timeZoneIdentifier: zoneChanged ? timeZone.identifier : configuredZone
        )
    }

    private static func initialCard(for deck: Deck) -> Card? {
        switch deck.displayConfig?.order ?? .sequential {
        case .sequential: return deck.activeCards.min { $0.ankiCardID < $1.ankiCardID }
        case .random: return deck.activeCards.randomElement()
        }
    }

    private static func plannedNextCard(after card: Card?, for deck: Deck) -> Card {
        switch deck.displayConfig?.order ?? .sequential {
        case .sequential: return nextSequentialCard(after: card, activeCards: deck.activeCards)
        case .random: return randomCard(excluding: card, activeCards: deck.activeCards)
        }
    }

    // MARK: - Reading a deck's schedule

    /// A schedule read must never create, advance, or top up rows. Mutation
    /// belongs to an explicitly locked transaction.
    static func readSchedule(for deck: Deck, in modelContext: ModelContext) {
        _ = try? validatedUnreachedEntries(for: deck, in: modelContext)
    }

    static func readSchedule(for deck: Deck, in modelContext: ModelContext, now: Date) throws {
        _ = now
        _ = modelContext
        _ = try validatedUnreachedEntries(for: deck, in: modelContext)
    }

    /// Creates/top-ups a schedule. Callers must hold the exclusive schedule
    /// lock and save the surrounding transaction exactly once.
    static func ensureSchedule(for deck: Deck, in modelContext: ModelContext) {
        try? topUp(deck, in: modelContext, now: Date())
    }

    static func ensureSchedule(for deck: Deck, in modelContext: ModelContext, now: Date) throws {
        try topUp(deck, in: modelContext, now: now)
    }

    // MARK: - Next

    /// Complete no-op while `deck.isPaused` -- no entry is consumed, no
    /// `projectedAt` changes, and the pointer/`highestReachedSequence` are
    /// untouched. This check happens before anything else. Also a no-op
    /// (not a crash) when the deck has zero active cards.
    static func next(_ deck: Deck, in modelContext: ModelContext) {
        try? next(deck, in: modelContext, now: Date())
    }

    static func next(_ deck: Deck, in modelContext: ModelContext, now: Date) throws {
        guard !deck.isPaused, !deck.activeCards.isEmpty else { return }
        let needsInitialSeed = try deck.activeHistoryEntry == nil &&
            deck.highestReachedSequence == nil && unreachedEntries(for: deck, in: modelContext).isEmpty
        if needsInitialSeed {
            try topUp(deck, in: modelContext, now: now)
            return
        }
        try reconcile(deck, in: modelContext, now: now)
        try topUp(deck, in: modelContext, now: now)

        let (targetSequence, overflow) = (deck.highestReachedSequence ?? 0).addingReportingOverflow(1)
        guard !overflow else { throw ScheduleError.malformed }
        guard let targetEntry = try entry(sequence: targetSequence, for: deck, in: modelContext) else {
            return
        }

        let intervalSeconds = try validatedIntervalSeconds(for: deck)
        targetEntry.projectedAt = now
        let laterEntries = try unreachedEntries(for: deck, in: modelContext)
            .filter { $0.sequence > targetSequence }
        var anchor = now
        for entry in laterEntries {
            anchor = try scheduledDate(after: anchor, seconds: intervalSeconds, deck: deck)
            entry.projectedAt = anchor
        }
        deck.activeHistoryEntry = targetEntry
        deck.highestReachedSequence = targetSequence
        try topUp(deck, in: modelContext, now: now)
    }

    /// Advances the persisted current pointer without rebuilding the future
    /// queue. Deck Detail uses this lightweight path for rapid taps, then
    /// debounces `rebuildFuture` so several taps cause one expensive rebuild.
    static func advanceImmediately(_ deck: Deck, in modelContext: ModelContext, now: Date) throws {
        guard !deck.isPaused, !deck.activeCards.isEmpty else { return }
        let needsInitialSeed = try deck.activeHistoryEntry == nil &&
            deck.highestReachedSequence == nil && unreachedEntries(for: deck, in: modelContext).isEmpty
        if needsInitialSeed {
            try topUp(deck, in: modelContext, now: now)
            return
        }
        try reconcileProgress(deck, in: modelContext, now: now)

        let (targetSequence, overflow) = (deck.highestReachedSequence ?? 0).addingReportingOverflow(1)
        guard !overflow else { throw ScheduleError.malformed }
        guard let targetEntry = try entry(sequence: targetSequence, for: deck, in: modelContext) else {
            return
        }

        targetEntry.projectedAt = now
        deck.activeHistoryEntry = targetEntry
        deck.highestReachedSequence = targetSequence
    }

    // MARK: - Reset primitive (order change / soft-delete reconciliation)

    /// Config `order` change: discards the unreached queue (always), then
    /// regenerates it per the new `order` if the deck isn't paused.
    static func handleOrderChange(for deck: Deck, in modelContext: ModelContext) throws {
        try discardUnreachedQueue(deck, in: modelContext)
        try topUp(deck, in: modelContext, now: Date())
    }

    /// Re-import soft-delete reconciliation for a deck that had one or
    /// more cards soft-deleted this import: discards the unreached queue
    /// (always, regardless of pause), clears the pointer if its own
    /// entry's card was among those soft-deleted (without deleting that
    /// row), then regenerates if the deck isn't paused.
    static func handleSoftDelete(for deck: Deck, in modelContext: ModelContext) throws {
        try discardUnreachedQueue(deck, in: modelContext)
        if let current = deck.activeHistoryEntry, let card = current.card, !card.isActive {
            deck.activeHistoryEntry = nil
        }
        try topUp(deck, in: modelContext, now: Date())
    }

    /// Deletes every `HistoryEntry` with `sequence > highestReachedSequence`
    /// for this deck (the unreached queue only -- the current entry and
    /// all real history are untouched). Always runs, paused or not.
    ///
    /// Clears each deleted entry's inverse link before deletion so an already
    /// registered deck does not retain tombstoned queue rows in this context.
    /// Queue reads themselves use bounded SwiftData queries.
    ///
    /// Rewinds `nextHistorySequence` back down to `highestReachedSequence +
    /// 1`: every discarded row's `sequence` was strictly greater than that,
    /// so those numbers are now unused by any surviving row anywhere (they
    /// were never reached, so they never became real history) and are free
    /// to be reissued. Without this, regeneration would keep counting up
    /// from wherever the discarded rows left off, leaving a permanent gap
    /// between `highestReachedSequence` and the next real row -- which
    /// breaks "Next" (decision 4), whose `sequence == highestReachedSequence
    /// + 1` lookup depends on that contiguity.
    static func discardUnreachedQueue(_ deck: Deck, in modelContext: ModelContext) throws {
        let toDiscard = try unreachedEntries(for: deck, in: modelContext)
        guard toDiscard.count <= queueSize else { throw ScheduleError.malformed }
        guard !toDiscard.isEmpty else { return }
        for entry in toDiscard {
            entry.deck = nil
            modelContext.delete(entry)
        }
        deck.nextHistorySequence = (deck.highestReachedSequence ?? 0).addingReportingOverflow(1).partialValue
    }

    // MARK: - Top-up

    /// Ensures at least `queueSize` unreached rows exist. No-op if the
    /// deck is paused, or if it has zero active cards (nothing to
    /// generate -- the deck simply stays below `queueSize`, possibly at 0,
    /// until it has an active card again).
    private static func topUp(
        _ deck: Deck,
        in modelContext: ModelContext,
        now: Date,
        anchorEmptyQueueAtNow: Bool = false
    ) throws {
        guard !deck.isPaused, !deck.activeCards.isEmpty else { return }
        if let config = deck.displayConfig, config.scheduleTimeZoneIdentifier == nil {
            config.scheduleTimeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        }
        var queue = try validatedUnreachedEntries(for: deck, in: modelContext)
        if deck.activeHistoryEntry == nil, deck.highestReachedSequence == nil, queue.isEmpty,
           let first = try generateNextEntry(for: deck, queue: queue, now: now, anchorEmptyQueueAtNow: true) {
            modelContext.insert(first)
            deck.activeHistoryEntry = first
            deck.highestReachedSequence = first.sequence
        }
        while queue.count < queueSize {
            guard let entry = try generateNextEntry(
                for: deck, queue: queue, now: now, anchorEmptyQueueAtNow: anchorEmptyQueueAtNow
            ) else { break }
            modelContext.insert(entry)
            queue.append(entry)
        }
    }

    static func context(for deck: Deck) throws -> ModelContext {
        guard let context = deck.modelContext else { throw ScheduleError.malformed }
        return context
    }

    static func entry(sequence: Int, for deck: Deck, in context: ModelContext) throws -> HistoryEntry? {
        let deckID = deck.persistentModelID
        var descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate<HistoryEntry> {
            $0.deck?.persistentModelID == deckID && $0.sequence == sequence
        })
        descriptor.fetchLimit = 1
        return try ScheduleQueryTrace.fetch(descriptor, in: context,
                                            kind: .current(sequence: sequence)).first
    }

    static func unreachedEntries(for deck: Deck, in context: ModelContext) throws -> [HistoryEntry] {
        let deckID = deck.persistentModelID
        let highest = deck.highestReachedSequence ?? 0
        var descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate<HistoryEntry> {
            $0.deck?.persistentModelID == deckID && $0.sequence > highest
        }, sortBy: [SortDescriptor(\HistoryEntry.sequence)])
        descriptor.fetchLimit = queueSize + 1
        return try ScheduleQueryTrace.fetch(descriptor, in: context, kind: .unreached)
    }

    /// Generates exactly one new queued entry, chained off "the reference
    /// entry" (ADR 0002, decision 4):
    /// 1. the highest-`sequence` entry among the *actual current* unreached
    ///    queue, regardless of when it was generated;
    /// 2. else the pointer's own entry, if the pointer is non-`nil`;
    /// 3. else (no unreached entry *and* the pointer is `nil`) there's no
    ///    reference entry -- the empty-queue rule applies. This check is
    ///    always on the pointer, never on `highestReachedSequence`.
    private static func generateNextEntry(
        for deck: Deck,
        queue: [HistoryEntry],
        now: Date,
        anchorEmptyQueueAtNow: Bool = false
    ) throws -> HistoryEntry? {
        let activeCards = deck.activeCards
        guard !activeCards.isEmpty else { return nil }

        let order = deck.displayConfig?.order ?? .sequential
        let intervalMinutes = deck.displayConfig?.intervalMinutes ?? DisplayConfig.defaultIntervalMinutes
        _ = try validatedIntervalSeconds(for: deck)

        if let reference = queue.last {
            return try chainedEntry(after: reference, order: order, intervalMinutes: intervalMinutes, activeCards: activeCards, deck: deck)
        }
        if let pointerEntry = deck.activeHistoryEntry, !anchorEmptyQueueAtNow {
            return try chainedEntry(after: pointerEntry, order: order, intervalMinutes: intervalMinutes, activeCards: activeCards, deck: deck)
        }

        // Empty-queue rule: never had a Next, or pointer just cleared and
        // queue fully discarded.
        let card: Card
        switch order {
        case .sequential:
            card = activeCards.min { $0.ankiCardID < $1.ankiCardID }!
        case .random:
            card = activeCards.randomElement()!
        }
        let (offset, offsetOverflow) = queue.count.addingReportingOverflow(1)
        guard !offsetOverflow else { throw ScheduleError.malformed }
        let (sequence, overflow) = (deck.highestReachedSequence ?? 0).addingReportingOverflow(offset)
        guard !overflow else { throw ScheduleError.malformed }
        let (nextSequence, nextOverflow) = sequence.addingReportingOverflow(1)
        guard !nextOverflow else { throw ScheduleError.malformed }
        deck.nextHistorySequence = nextSequence
        let projectedAt = now
        return HistoryEntry(sequence: sequence, projectedAt: projectedAt, card: card, deck: deck)
    }

    static func isRenderable(_ entry: HistoryEntry) -> Bool {
        guard let card = entry.card, card.isActive, let note = card.note, note.isActive else { return false }
        return card.deck?.persistentModelID == entry.deck?.persistentModelID
    }

    static func validatedUnreachedEntries(for deck: Deck) throws -> [HistoryEntry] {
        try validatedUnreachedEntries(for: deck, in: context(for: deck))
    }

    static func validatedUnreachedEntries(for deck: Deck, in context: ModelContext) throws -> [HistoryEntry] {
        let highest = deck.highestReachedSequence ?? 0
        let entries = try unreachedEntries(for: deck, in: context)
        guard entries.count <= queueSize else { throw ScheduleError.malformed }
        let (firstExpected, overflow) = highest.addingReportingOverflow(1)
        guard !overflow else { throw ScheduleError.malformed }
        var expected = firstExpected
        var previousDate: Date?
        for entry in entries {
            guard entry.sequence == expected,
                  entry.deck?.persistentModelID == deck.persistentModelID,
                  isRenderable(entry),
                  previousDate.map({ entry.projectedAt > $0 }) ?? true
            else { throw ScheduleError.malformed }
            previousDate = entry.projectedAt
            let increment = expected.addingReportingOverflow(1)
            if entry !== entries.last { guard !increment.overflow else { throw ScheduleError.malformed } }
            expected = increment.partialValue
        }
        return entries
    }

    static func reconcile(_ deck: Deck, in modelContext: ModelContext, now: Date) throws {
        try reconcileProgress(deck, in: modelContext, now: now)
        try topUp(deck, in: modelContext, now: now)
    }

    private static func reconcileProgress(_ deck: Deck, in modelContext: ModelContext, now: Date) throws {
        guard !deck.isPaused, !deck.activeCards.isEmpty else { return }
        _ = try validatedIntervalSeconds(for: deck)
        if let config = deck.displayConfig,
           config.scheduleTimeZoneIdentifier != TimeZone.autoupdatingCurrent.identifier {
            if config.sleepEnabled {
                try rebuildFuture(
                    for: deck,
                    in: modelContext,
                    now: now,
                    timeZone: .autoupdatingCurrent
                )
            } else {
                config.scheduleTimeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
            }
        }
        let entries = try validatedUnreachedEntries(for: deck, in: modelContext)
        let due = entries.prefix { $0.projectedAt <= now }
        if let effective = due.last {
            deck.highestReachedSequence = effective.sequence
            deck.activeHistoryEntry = effective
        }
    }

    static func setPaused(_ paused: Bool, deck: Deck, in modelContext: ModelContext, now: Date) throws {
        if paused {
            try discardUnreachedQueue(deck, in: modelContext)
            deck.isPaused = true
        } else {
            deck.isPaused = false
            guard !deck.activeCards.isEmpty else { return }
            if let current = deck.activeHistoryEntry {
                let resumed = try chainedEntry(
                    after: current,
                    order: deck.displayConfig?.order ?? .sequential,
                    intervalMinutes: deck.displayConfig?.intervalMinutes ?? DisplayConfig.defaultIntervalMinutes,
                    activeCards: deck.activeCards,
                    deck: deck,
                    projectedAt: now
                )
                modelContext.insert(resumed)
                deck.activeHistoryEntry = resumed
                deck.highestReachedSequence = resumed.sequence
            } else {
                try topUp(deck, in: modelContext, now: now, anchorEmptyQueueAtNow: true)
            }
            try topUp(deck, in: modelContext, now: now)
        }
    }

    /// Replaces only automatic future rows after a schedule-setting edit.
    /// The persisted current row and reached history remain untouched.
    static func rebuildFuture(
        for deck: Deck,
        in modelContext: ModelContext,
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws {
        _ = try validatedIntervalSeconds(for: deck)
        try deck.displayConfig?.validateSleep()
        try discardUnreachedQueue(deck, in: modelContext)
        deck.displayConfig?.scheduleTimeZoneIdentifier = timeZone.identifier
        if !deck.isPaused, let current = deck.activeHistoryEntry {
            let first = try chainedEntry(
                after: current,
                order: deck.displayConfig?.order ?? .sequential,
                intervalMinutes: deck.displayConfig?.intervalMinutes ?? DisplayConfig.defaultIntervalMinutes,
                activeCards: deck.activeCards,
                deck: deck,
                anchorDate: now
            )
            modelContext.insert(first)
        }
        try topUp(deck, in: modelContext, now: now, anchorEmptyQueueAtNow: true)
    }

    private static func chainedEntry(
        after reference: HistoryEntry,
        order: DisplayOrder,
        intervalMinutes: Int,
        activeCards: [Card],
        deck: Deck,
        anchorDate: Date? = nil,
        projectedAt explicitProjectedAt: Date? = nil
    ) throws -> HistoryEntry {
        let card: Card
        switch order {
        case .sequential:
            card = nextSequentialCard(after: reference.card, activeCards: activeCards)
        case .random:
            card = randomCard(excluding: reference.card, activeCards: activeCards)
        }
        let sequence = deck.nextHistorySequence
        let (nextSequence, overflow) = sequence.addingReportingOverflow(1)
        guard !overflow else { throw ScheduleError.malformed }
        deck.nextHistorySequence = nextSequence
        let seconds = try validatedIntervalSeconds(intervalMinutes)
        let projectedAt = try explicitProjectedAt ?? scheduledDate(after: anchorDate ?? reference.projectedAt, seconds: seconds, deck: deck)
        return HistoryEntry(sequence: sequence, projectedAt: projectedAt, card: card, deck: deck)
    }

    private static func validatedIntervalSeconds(for deck: Deck) throws -> TimeInterval {
        try validatedIntervalSeconds(deck.displayConfig?.intervalMinutes ?? DisplayConfig.defaultIntervalMinutes)
    }

    private static func validatedIntervalSeconds(_ minutes: Int) throws -> TimeInterval {
        guard (DisplayConfig.minimumIntervalMinutes...DisplayConfig.maximumIntervalMinutes).contains(minutes) else {
            throw ScheduleError.malformed
        }
        let (seconds, overflow) = minutes.multipliedReportingOverflow(by: 60)
        guard !overflow else { throw ScheduleError.malformed }
        return TimeInterval(seconds)
    }

    private static func checkedDate(_ date: Date, adding interval: TimeInterval) throws -> Date {
        let result = date.addingTimeInterval(interval)
        guard result.timeIntervalSinceReferenceDate.isFinite else { throw ScheduleError.malformed }
        return result
    }

    private static func scheduledDate(
        after date: Date,
        seconds: TimeInterval,
        deck: Deck,
        timeZone overrideTimeZone: TimeZone? = nil
    ) throws -> Date {
        guard let config = deck.displayConfig else { return try checkedDate(date, adding: seconds) }
        let zone = overrideTimeZone ?? TimeZone(identifier: config.scheduleTimeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier)
            ?? TimeZone.autoupdatingCurrent
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = zone
        return try SleepSchedule(
            enabled: config.sleepEnabled,
            startMinute: config.sleepStartMinute,
            endMinute: config.sleepEndMinute
        ).addingAwakeSeconds(seconds, to: date, calendar: calendar, timeZone: zone)
    }

    /// Next active card after `card` by `ankiCardID`, wrapping to the
    /// first after the last. Falls back to the lowest-`ankiCardID` active
    /// card if `card` is `nil` or no longer found among active cards.
    private static func nextSequentialCard(after card: Card?, activeCards: [Card]) -> Card {
        let sorted = activeCards.sorted { $0.ankiCardID < $1.ankiCardID }
        guard let card, let index = sorted.firstIndex(where: { $0.persistentModelID == card.persistentModelID }) else {
            return sorted[0]
        }
        return sorted[(index + 1) % sorted.count]
    }

    /// A random active card other than `card`, whenever more than one
    /// active card exists; otherwise (or if `card` is `nil`) any active
    /// card.
    private static func randomCard(excluding card: Card?, activeCards: [Card]) -> Card {
        if let card, activeCards.count > 1 {
            let others = activeCards.filter { $0.persistentModelID != card.persistentModelID }
            if let picked = others.randomElement() {
                return picked
            }
        }
        return activeCards.randomElement()!
    }
}
