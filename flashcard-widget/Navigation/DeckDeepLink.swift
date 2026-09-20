import Foundation

enum DeckDeepLink {
    static func parse(_ url: URL) -> Int64? {
        guard
            url.scheme == "flashcard-widget",
            url.host == "deck",
            url.query == nil,
            url.fragment == nil
        else { return nil }

        let path = url.path
        guard path.first == "/", path.last != "/" else { return nil }
        let raw = String(path.dropFirst())
        guard !raw.isEmpty else { return nil }
        if raw == "0" {
            return url.absoluteString == "flashcard-widget://deck/0" ? 0 : nil
        }
        guard raw.first.map({ ("1"..."9").contains(String($0)) }) == true,
              raw.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        guard let value = Int64(raw), url.absoluteString == "flashcard-widget://deck/\(value)" else {
            return nil
        }
        return value
    }

    static func url(for ankiDeckID: Int64) -> URL? {
        guard ankiDeckID >= 0 else { return nil }
        return URL(string: "flashcard-widget://deck/\(ankiDeckID)")
    }
}
