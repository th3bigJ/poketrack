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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if fillBackground {
                    RoundedRectangle(cornerRadius: geo.size.width * 0.16, style: .continuous)
                        .fill(lineColor.opacity(colorScheme == .dark ? 0.10 : 0.07))
                }

                RoundedRectangle(cornerRadius: geo.size.width * 0.16, style: .continuous)
                    .stroke(lineColor, lineWidth: 1.5)

                // Inner top eyebrow line — small horizontal mark that
                // mimics a card's title row.
                VStack(spacing: geo.size.width * 0.06) {
                    Capsule()
                        .fill(lineColor.opacity(0.55))
                        .frame(width: geo.size.width * 0.32, height: 2)

                    Text("PREMIUM")
                        .font(.system(size: geo.size.width * 0.10, weight: .semibold, design: .rounded))
                        .tracking(geo.size.width * 0.02)
                        .foregroundStyle(lineColor)

                    Text("BINDR")
                        .font(.system(size: geo.size.width * 0.20, weight: .bold, design: .default))
                        .tracking(geo.size.width * 0.012)
                        .foregroundStyle(lineColor)

                    // Inner bottom mark — symmetry with the eyebrow line.
                    Capsule()
                        .fill(lineColor.opacity(0.55))
                        .frame(width: geo.size.width * 0.18, height: 2)
                }
                .padding(.vertical, geo.size.width * 0.18)
            }
        }
        .aspectRatio(110.0 / 140.0, contentMode: .fit)
    }
}
