import SwiftUI

// MARK: - PremiumLineCardBadge
//
// Replaces the stock gold-crown graphic used on every premium surface
// with a minimalist line-art mark: a card silhouette holding the BINDR
// wordmark and a small "PREMIUM" eyebrow.
//
// Why line-art:
//   * The previous gold crown read as a generic stock paywall asset.
//   * Brand-tinted line work matches the rest of the onboarding flow
//     (monochrome icons, native checkmarks), keeping the system coherent.
//   * Scales to any size — no rasterised crown texture to maintain.
//
// Customisation:
//   * `tint` accepts the colour of the line work + wordmark.
//   * `fillBackground` (default `true`) shows the soft accent-tinted
//     card backdrop. Set `false` for an outline-only treatment over
//     existing surfaces.

struct PremiumLineCardBadge: View {
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var tint: Color? = nil
    var fillBackground: Bool = true

    private var lineColor: Color { tint ?? accent }
    private var usesThemeGradient: Bool { tint == nil }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if fillBackground {
                    RoundedRectangle(cornerRadius: geo.size.width * 0.16, style: .continuous)
                        .bindrAccentFill(
                            lineColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                            usesLogoGradient: usesThemeGradient,
                            logoOpacity: colorScheme == .dark ? 0.12 : 0.08
                        )
                }

                RoundedRectangle(cornerRadius: geo.size.width * 0.16, style: .continuous)
                    .bindrAccentStroke(lineColor, lineWidth: 1.5, usesLogoGradient: usesThemeGradient)

                // Inner top eyebrow line — small horizontal mark that
                // mimics a card's title row.
                VStack(spacing: geo.size.width * 0.05) {
                    Capsule()
                        .bindrAccentFill(
                            lineColor.opacity(0.55),
                            usesLogoGradient: usesThemeGradient,
                            logoOpacity: 0.55
                        )
                        .frame(width: geo.size.width * 0.32, height: 2)

                    premiumEyebrow(width: geo.size.width)

                    BindrBrandLogoView(maxWidth: geo.size.width * 0.78)
                        .padding(.vertical, geo.size.width * 0.02)
                }
                .padding(.vertical, geo.size.width * 0.12)
            }
        }
        .aspectRatio(110.0 / 140.0, contentMode: .fit)
    }

    @ViewBuilder
    private func premiumEyebrow(width: CGFloat) -> some View {
        let label = Text("PREMIUM")
            .font(.system(size: width * 0.10, weight: .semibold, design: .rounded))
            .tracking(width * 0.02)

        if usesThemeGradient {
            label.bindrAccentForeground(lineColor)
        } else {
            label.foregroundStyle(lineColor)
        }
    }
}
