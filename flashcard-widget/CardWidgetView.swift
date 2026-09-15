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
        VStack(alignment: .leading, spacing: 3) {
            Text(content.primary)
                .font(.headline.weight(.semibold))
                .foregroundStyle(content.usesPrimaryPlaceholder ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 2)

            if let secondary = content.secondary {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let tertiary = content.tertiary {
                Text(tertiary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: 260, maxHeight: 108, alignment: .leading)
        .aspectRatio(2.4, contentMode: .fit)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
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
