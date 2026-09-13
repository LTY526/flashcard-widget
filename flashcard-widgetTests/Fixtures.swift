//
//  Fixtures.swift
//  flashcard-widgetTests
//
//  Locates the hand-built `.apkg` fixtures checked into this test target.
//  See the fixture generation notes in the PR description / import report
//  for how each one was constructed and why (no network access to a real
//  Anki install was available, so these are schema-accurate constructions
//  rather than real Anki exports).
//

import Foundation

enum Fixtures {
    private final class BundleMarker {}

    static func url(_ name: String) -> URL {
        guard let url = Bundle(for: BundleMarker.self).url(forResource: name, withExtension: "apkg") else {
            fatalError("Missing fixture \(name).apkg in test bundle -- check target membership")
        }
        return url
    }
}
