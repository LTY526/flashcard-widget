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
    let quaternary: String?
    let usesPrimaryPlaceholder: Bool

    static func resolve(
        primary: String?,
        secondary: String?,
        tertiary: String?,
        quaternary: String? = nil
    ) -> CardWidgetContent {
        CardWidgetContent(
            primary: primary ?? primaryPlaceholder,
            secondary: secondary,
            tertiary: tertiary,
            quaternary: quaternary,
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
        quaternary: String? = nil,
        presentation: CardWidgetPresentation = .lockScreen
    ) {
        content = CardWidgetContent.resolve(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            quaternary: quaternary
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

            if presentation == .inApp {
                Spacer(minLength: 12)
            }

            if let secondary = content.secondary {
                Text(secondary)
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(presentation == .lockScreen ? 1 : 2)
            } else if presentation == .lockScreen {
                Text("—")
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if presentation == .lockScreen {
                Text(content.tertiary ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else if let tertiary = content.tertiary {
                Text(tertiary)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if presentation == .inApp, let quaternary = content.quaternary {
                Text(quaternary)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
            CardWidgetView(
                primary: "A very long primary value that scales before truncating",
                secondary: "A very long secondary value that truncates at the trailing edge",
                tertiary: "A very long tertiary value that truncates at the trailing edge"
            )
            CardWidgetView(primary: "Missing optional rows", secondary: nil, tertiary: nil)
            CardWidgetView(
                primary: "Unlimited in-app fields",
                secondary: "Secondary",
                tertiary: "Tertiary text\ncontinues over as many\nlines as it needs.",
                quaternary: "Quaternary text\nalso remains complete\nin the app.",
                presentation: .inApp
            )
        }
        .padding()
    }
}
