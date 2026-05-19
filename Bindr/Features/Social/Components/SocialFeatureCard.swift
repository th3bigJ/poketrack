import SwiftUI

// MARK: - SocialFeatureCard
//
// Feature pill used by `SocialLandingView` and the social-discovery
// surface in onboarding. Refactor brief:
//   * Pastel-square icon backdrops removed. Icons render as monochrome
//     SF Symbols tinted with the accent color (or an explicit override).
//   * Numeric index moved to a borderless caption, no monospaced badge.
//   * Title weight stays at .semibold; subtitle bumped to .secondary
//     at 13pt for proper iOS contrast.

struct SocialFeatureCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let icon: String
    let title: String
    let description: String
    /// Optional accent override. When nil, the icon uses the theme accent.
    let tint: Color?
    let index: Int

    init(
        icon: String,
        title: String,
        description: String,
        tint: Color? = nil,
        index: Int
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.tint = tint
        self.index = index
    }

    var body: some View {
        HStack(spacing: BindrSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(tint ?? accent)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Borderless numeric metadata — no pill, no monospaced design.
            Text(String(format: "%02d", index))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
    }
}

// MARK: - Section header

/// Small caption used above hero blocks. Drops the previous tracking-2
/// heavy treatment in favour of a calmer, more readable iOS metadata feel.
struct SocialSectionEyebrow: View {
    @Environment(\.bindrAccent) private var accent
    let title: String
    var accentDot: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if accentDot {
                Circle()
                    .fill(BindrPalette.ownedGreen)
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
