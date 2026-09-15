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

enum CardWidgetPresentation {
    case lockScreen
    case inApp
}

struct CardWidgetView: View {
    private let content: CardWidgetContent
    private let presentation: CardWidgetPresentation

    init(
        primary: String?,
        secondary: String?,
        tertiary: String?,
        presentation: CardWidgetPresentation = .lockScreen
    ) {
        content = CardWidgetContent.resolve(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary
        )
        self.presentation = presentation
    }

    var body: some View {
        switch presentation {
        case .lockScreen:
            cardContent
                .padding(8)
                .frame(width: 160, height: 72, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator, lineWidth: 0.5)
                }
        case .inApp:
            cardContent
                .padding()
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.separator, lineWidth: 0.5)
                }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: presentation == .lockScreen ? 2 : 8) {
            Text(content.primary)
                .font(primaryFont)
                .foregroundStyle(content.usesPrimaryPlaceholder ? .secondary : .primary)
                .lineLimit(presentation == .lockScreen ? 1 : 2)
                .minimumScaleFactor(0.75)

            Spacer(minLength: presentation == .lockScreen ? 1 : 12)

            if let secondary = content.secondary {
                Text(secondary)
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(presentation == .lockScreen ? 1 : 2)
            }

            if presentation == .inApp, let tertiary = content.tertiary {
                Text(tertiary)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var primaryFont: Font {
        presentation == .lockScreen ? .caption.weight(.semibold) : .title2.weight(.semibold)
    }

    private var secondaryFont: Font {
        presentation == .lockScreen ? .caption2 : .body
    }
}

#Preview("Card variants") {
    ScrollView {
        VStack(spacing: 16) {
            CardWidgetView(
                primary: "犬",
                secondary: "dog",
                tertiary: "いぬ",
                presentation: .inApp
            )
            CardWidgetView(primary: "猫", secondary: "cat", tertiary: nil)
            CardWidgetView(primary: "鳥", secondary: nil, tertiary: nil)
            CardWidgetView(primary: nil, secondary: "Unmapped note type", tertiary: nil)
        }
        .padding()
    }
}
