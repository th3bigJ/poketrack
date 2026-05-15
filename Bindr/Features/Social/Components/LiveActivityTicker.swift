import SwiftUI

// MARK: - LiveActivityTicker
//
// Continuously vertically-scrolling ticker of "live" social events used on
// the SocialLandingView and Onboarding social-discovery screen. The events
// are placeholder fixtures — the same shape that `SocialFeedService` posts
// later get rendered through this same row component, so it reads as a real
// preview of the feed instead of marketing chrome.
//
// Performance notes:
//   * One `Timer` drives the vertical offset transitions; a single ticker
//     instance runs across the landing surface so we don't fan out into N
//     tickers each holding their own `withAnimation` loop.
//   * Rows use `id(item.id)` so SwiftUI animates the diff rather than
//     measuring + transitioning every child on each tick.

struct LiveActivityTicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    private let items: [LiveActivityItem]
    @State private var topIndex: Int = 0

    init(items: [LiveActivityItem] = LiveActivityItem.placeholders) {
        self.items = items
    }

    var body: some View {
        VStack(spacing: BindrSpacing.sm) {
            ForEach(visibleSlice(), id: \.slotID) { slot in
                LiveActivityRow(item: slot.item)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous))
        .task {
            // `.task` cancels automatically when the view disappears, so
            // navigating away from the landing surface stops the ticker
            // cleanly rather than leaking a free-running Task per visit.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                if Task.isCancelled { break }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                    topIndex = (topIndex + 1) % max(items.count, 1)
                }
            }
        }
    }

    /// 3-item window. Wraps so the loop never empties.
    private func visibleSlice() -> [VisibleSlot] {
        guard !items.isEmpty else { return [] }
        return (0..<3).map { offset in
            let index = (topIndex + offset) % items.count
            return VisibleSlot(slotID: "\(items[index].id)-\(topIndex + offset)", item: items[index])
        }
    }

    private struct VisibleSlot: Identifiable {
        let slotID: String
        let item: LiveActivityItem
        var id: String { slotID }
    }
}

// MARK: - Row

private struct LiveActivityRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent
    let item: LiveActivityItem

    var body: some View {
        HStack(spacing: BindrSpacing.md) {
            ZStack {
                Circle()
                    .fill(item.kind.tint.opacity(colorScheme == .dark ? 0.18 : 0.14))
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.actor)
                        .font(.system(size: 14, weight: .semibold))
                    Text(item.verb)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                Text(item.subject)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Circle()
                    .fill(BindrPalette.ownedGreen)
                    .frame(width: 6, height: 6)
                    .pulseGlow()
                Text(item.timestamp)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: BindrRadius.lg, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: BindrRadius.lg, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.07), lineWidth: 0.5)
        }
    }
}

// MARK: - Model

struct LiveActivityItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case pull
        case trade
        case grail
        case listing
        case wishlist

        var symbol: String {
            switch self {
            case .pull:     return "sparkles"
            case .trade:    return "arrow.left.arrow.right"
            case .grail:    return "crown.fill"
            case .listing:  return "tag.fill"
            case .wishlist: return "heart.fill"
            }
        }

        var tint: Color {
            switch self {
            case .pull:     return BindrPalette.ownedGreen
            case .trade:    return BindrPalette.deckBlue
            case .grail:    return BindrPalette.binderGold
            case .listing:  return BindrPalette.binderGold
            case .wishlist: return BindrPalette.wishlistViolet
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let actor: String
    let verb: String
    let subject: String
    let timestamp: String

    static let placeholders: [LiveActivityItem] = [
        .init(kind: .pull,     actor: "@kasey",     verb: "pulled a",      subject: "Charizard ex • Hyper Rare", timestamp: "now"),
        .init(kind: .trade,    actor: "@mike.tcg",  verb: "locked in a trade for", subject: "Pikachu illustrator", timestamp: "12s"),
        .init(kind: .grail,    actor: "@robin",     verb: "listed a grail —", subject: "Moonbreon Alt Art", timestamp: "30s"),
        .init(kind: .wishlist, actor: "@cass",      verb: "added to wishlist",      subject: "Luffy Manga Rare", timestamp: "44s"),
        .init(kind: .listing,  actor: "@elena",     verb: "listed",                 subject: "Umbreon VMAX Alt", timestamp: "1m"),
        .init(kind: .pull,     actor: "@dre",       verb: "pulled a",               subject: "Lugia V Alt Art",  timestamp: "1m"),
        .init(kind: .trade,    actor: "@kira",      verb: "completed a trade for",  subject: "Iono SR ⇄ Mew ex", timestamp: "2m"),
        .init(kind: .grail,    actor: "@max",       verb: "is hunting",             subject: "Trainer Gallery Eevee", timestamp: "2m"),
    ]
}

// MARK: - Pulse glow modifier

private struct PulseGlow: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .shadow(color: BindrPalette.ownedGreen.opacity(pulse ? 0.65 : 0.0), radius: pulse ? 5 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private extension View {
    func pulseGlow() -> some View { modifier(PulseGlow()) }
}
