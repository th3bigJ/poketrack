import SwiftUI

extension SocialProfile {
    /// Display name when set, otherwise the username — used in trade context copy.
    var shortDisplayName: String {
        if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            return displayName
        }
        return username
    }
}

/// Contextual trade prompt shown below card action buttons when a page supplies trade intent.
struct CardTradeContext {
    let message: String
    let onTrade: (Card) -> Void

    static func friendHas(name: String, onTrade: @escaping (Card) -> Void) -> CardTradeContext {
        CardTradeContext(message: "\(name) has this card", onTrade: onTrade)
    }

    static func friendWants(name: String, onTrade: @escaping (Card) -> Void) -> CardTradeContext {
        CardTradeContext(message: "\(name) wants this card", onTrade: onTrade)
    }

    static func peopleHave(count: Int, onTrade: @escaping (Card) -> Void) -> CardTradeContext {
        let noun = count == 1 ? "person has" : "people have"
        return CardTradeContext(message: "\(count) \(noun) this card", onTrade: onTrade)
    }

    static func peopleWant(count: Int, onTrade: @escaping (Card) -> Void) -> CardTradeContext {
        let noun = count == 1 ? "person wants" : "people want"
        return CardTradeContext(message: "\(count) \(noun) this card", onTrade: onTrade)
    }
}

struct CardTradeContextRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let card: Card
    let context: CardTradeContext

    private let tradeTint = Color(red: 0.52, green: 0.44, blue: 0.94)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tradeTint)

            Text(context.message)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Button {
                Haptics.lightImpact()
                context.onTrade(card)
            } label: {
                Text("Trade")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(tradeTint, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCardStyle(cornerRadius: 18, interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(context.message). Trade.")
        .accessibilityAddTraits(.isButton)
    }
}
