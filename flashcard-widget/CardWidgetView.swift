//
//  CardWidgetView.swift
//  flashcard-widget
//
//  Shared presentation for an in-app card preview. It accepts plain text
//  values so a future widget can reuse the presentation without depending on
//  live SwiftData models.
//

import SwiftUI

struct CardWidgetContent: Equatable, Sendable {
    static let primaryPlaceholder = "No field mapped to Primary yet"

    let primary: String
    let secondary: String?
    let tertiary: String?
    let usesPrimaryPlaceholder: Bool

    static func resolve(
        primary: String?,
        secondary: String?,
        tertiary: String?
    ) -> CardWidgetContent {
        CardWidgetContent(
            primary: primary ?? primaryPlaceholder,
            secondary: secondary,
            tertiary: tertiary,
            usesPrimaryPlaceholder: primary == nil
        )
    }
}

struct CardWidgetView: View {
    private let content: CardWidgetContent

    init(primary: String?, secondary: String?, tertiary: String?) {
        content = CardWidgetContent.resolve(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.primary)
                .font(.title2.weight(.semibold))
                .foregroundStyle(content.usesPrimaryPlaceholder ? .secondary : .primary)

            Spacer(minLength: 24)

            if let secondary = content.secondary {
                Text(secondary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let tertiary = content.tertiary {
                Text(tertiary)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Card variants") {
    ScrollView {
        VStack(spacing: 16) {
            CardWidgetView(primary: "犬", secondary: "dog", tertiary: "いぬ")
            CardWidgetView(primary: "猫", secondary: "cat", tertiary: nil)
            CardWidgetView(primary: "鳥", secondary: nil, tertiary: nil)
            CardWidgetView(primary: nil, secondary: "Unmapped note type", tertiary: nil)
        }
        .padding()
    }
}
