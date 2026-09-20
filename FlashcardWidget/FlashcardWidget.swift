import SwiftData
import SwiftUI
import WidgetKit

enum WidgetCardState: Sendable {
    case failure
    case chooseDeck
    case needsMapping
    case empty
    case paused
    case brokenSchedule
    case card(primary: String, secondary: String?, tertiary: String?)

    var visibleText: String {
        switch self {
        case .failure: "Flashcards are unavailable"
        case .chooseDeck: "Choose a deck"
        case .needsMapping: "Field mapping required"
        case .empty: "No cards in this deck"
        case .paused: "Deck paused"
        case .brokenSchedule: "Schedule unavailable — open the app"
        case .card(let primary, let secondary, let tertiary):
            [primary, secondary, tertiary].compactMap { $0 }.joined(separator: ". ")
        }
    }
}

struct FlashcardEntry: TimelineEntry, Sendable {
    let date: Date
    let state: WidgetCardState
    let deckID: Int64?
}

struct Provider: AppIntentTimelineProvider {
    private struct TimelineData: Sendable {
        let entries: [FlashcardEntry]
        let reloadAfter: Date?
    }

    func placeholder(in context: Context) -> FlashcardEntry {
        FlashcardEntry(date: .now, state: .card(primary: "Front", secondary: "Back", tertiary: "Detail"), deckID: nil)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> FlashcardEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        let now = Date()
        guard let deckID = configuration.deck?.ankiDeckID else {
            return FlashcardEntry(date: now, state: .chooseDeck, deckID: nil)
        }
        do {
            return try await loadTimeline(deckID: deckID, now: now).entries[0]
        } catch {
            return FlashcardEntry(date: now, state: .failure, deckID: deckID)
        }
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<FlashcardEntry> {
        let now = Date()
        guard let deckID = configuration.deck?.ankiDeckID else {
            return Timeline(entries: [FlashcardEntry(date: now, state: .chooseDeck, deckID: nil)], policy: .never)
        }
        do {
            let data = try await loadTimeline(deckID: deckID, now: now)
            let policy = data.reloadAfter.map(TimelineReloadPolicy.after) ?? .never
            return Timeline(entries: data.entries, policy: policy)
        } catch {
            return Timeline(
                entries: [FlashcardEntry(date: now, state: .failure, deckID: deckID)],
                policy: .after(now.addingTimeInterval(15 * 60))
            )
        }
    }

    private func loadTimeline(deckID: Int64, now: Date) async throws -> TimelineData {
        let lock = try ScheduleFileLock.shared()
        return try await lock.withLock(mode: .shared) {
            let container = try SharedModelContainer.makeShared()
            let context = ModelContext(container)
            let decks = try context.fetch(FetchDescriptor<Deck>())
            guard let deck = decks.first(where: { $0.ankiDeckID == deckID }) else {
                return TimelineData(
                    entries: [FlashcardEntry(date: now, state: .chooseDeck, deckID: deckID)],
                    reloadAfter: nil
                )
            }
            let plan = ProviderTimelinePlan.make(deck: deck, now: now)
            let selected: [ScheduledCardValue]
            switch plan.selection {
            case .cards(let cards): selected = cards
            case .needsMapping: return Self.stateTimeline(.needsMapping, deckID: deckID, now: now)
            case .empty: return Self.stateTimeline(.empty, deckID: deckID, now: now)
            case .paused: return Self.stateTimeline(.paused, deckID: deckID, now: now)
            case .brokenSchedule: return Self.stateTimeline(.brokenSchedule, deckID: deckID, now: now)
            }
            var entries: [FlashcardEntry] = []
            for entry in selected {
                guard let primary = entry.primary else {
                    return Self.stateTimeline(.brokenSchedule, deckID: deckID, now: now)
                }
                entries.append(FlashcardEntry(
                    date: entry.date,
                    state: .card(primary: primary, secondary: entry.secondary, tertiary: entry.tertiary),
                    deckID: deckID
                ))
            }
            return TimelineData(entries: entries, reloadAfter: plan.reloadAfter)
        }
    }

    private static func stateTimeline(
        _ state: WidgetCardState,
        deckID: Int64,
        now: Date
    ) -> TimelineData {
        TimelineData(
            entries: [FlashcardEntry(date: now, state: state, deckID: deckID)],
            reloadAfter: nil
        )
    }
}

struct FlashcardWidgetEntryView: View {
    let entry: FlashcardEntry

    var body: some View {
        Group {
            switch entry.state {
            case .card(let primary, let secondary, let tertiary):
                VStack(alignment: .leading, spacing: 2) {
                    Text(primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.75)
                    Text(secondary ?? "—")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(tertiary ?? "—")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([primary, secondary, tertiary].compactMap { $0 }.joined(separator: ". "))
            default:
                Text(entry.state.visibleText)
                    .accessibilityLabel(entry.state.visibleText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .widgetURL(entry.deckID.flatMap { URL(string: "flashcard-widget://deck/\($0)") })
    }
}

struct FlashcardWidget: Widget {
    static let kind = "FlashcardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            FlashcardWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Flashcard")
        .description("See the current card from a selected deck.")
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    FlashcardWidget()
} timeline: {
    FlashcardEntry(date: .now, state: .card(primary: "Cell", secondary: "Basic unit of life", tertiary: "Biology"), deckID: 42)
    FlashcardEntry(date: .now, state: .brokenSchedule, deckID: nil)
}
