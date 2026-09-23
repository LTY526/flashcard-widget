/// The single source of truth for controls rendered by each Deck Detail mode.
/// DeckDetailView and DisplayConfigSection iterate these lists directly.
enum DeckDetailControl: Hashable, Identifiable {
    case currentCard
    case next
    case pause
    case schedule
    case order
    case interval
    case sleepEnabled
    case sleepStart
    case wakeTime
    case fieldMapping

    var id: Self { self }

    static func visible(in mode: DeckDetailRoute.Mode) -> [Self] {
        switch mode {
        case .current:
            [.currentCard, .next, .pause]
        case .schedule:
            [.schedule]
        case .config:
            [.order, .interval, .sleepEnabled, .sleepStart, .wakeTime, .fieldMapping]
        }
    }

    var isConfigurationSetting: Bool {
        switch self {
        case .order, .interval, .sleepEnabled, .sleepStart, .wakeTime: true
        default: false
        }
    }
}
