import SwiftUI

// MARK: - OnboardingFeatureRow
//
// Replaces every variation of "pastel square + coloured icon" feature
// row across welcome / offline / notifications / premium. The icon now
// renders as a monochrome SF Symbol in the user's accent colour, with no
// coloured square backdrop — leaning into a clean iOS metadata feel.
//
// Visual contract:
//   * 28pt SF Symbol, accent tint, no backdrop tile.
//   * Title: system 15 / semibold, primary color.
//   * Subtitle: system 13 / regular, `.secondary` (boosted from the
//     previous `12pt .tertiary` for proper iOS contrast / readability).
//   * Row sits inside a glass card for grouping; combining rows in a
//     VStack with `BindrSpacing.sm` keeps them as discrete tiles.

struct OnboardingFeatureRow: View {
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    let description: String

    /// Optional override; defaults to `accent`. Pass `.primary` for a
    /// fully monochrome variant.
    var iconTint: Color? = nil

    var body: some View {
        HStack(spacing: BindrSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(iconTint ?? accent)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.lg, interactive: false)
    }
}

// MARK: - OnboardingHeadline

/// Standardised onboarding headline block. Replaces the heavier
/// 36pt-heavy + tracking treatment used in earlier iterations.
struct OnboardingHeadline: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BindrSpacing.sm) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .lineSpacing(-1)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
