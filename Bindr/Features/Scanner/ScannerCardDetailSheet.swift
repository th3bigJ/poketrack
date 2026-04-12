import SwiftUI

// MARK: - Glass bar (matches `CardBrowseDetailView` header)

/// Same material stack as the card detail sheet header: Liquid Glass (iOS 26+) or frosted material, plus a light scrim for title legibility.
struct CardDetailStyleGlassBarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if #available(iOS 26.0, *) {
                Rectangle()
                    .fill(Color.clear)
                    .glassEffect(.regular, in: Rectangle())
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            Rectangle()
                .fill(headerFullWidthDimStyle)
                .opacity(colorScheme == .dark ? 0.38 : 0.30)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    private var headerFullWidthDimStyle: LinearGradient {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.24),
                    Color.white.opacity(0.17),
                    Color.white.opacity(0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.11),
                    Color.black.opacity(0.06),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

