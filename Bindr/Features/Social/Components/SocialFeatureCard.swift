import SwiftUI

// MARK: - SocialFeatureCard
//
// Reusable feature pill used by both `SocialLandingView` and the social
// page of the onboarding flow. Replaces the dense divider-separated list
// from the original placeholder with discrete glass tiles so the surface
// reads as "modules of the social experience" rather than a settings list.
//
// Visual contract:
//   * Glass card body (same modifier the tab bar / dashboard cards use).
//   * Accent-tinted icon chip on the leading edge.
//   * Trailing chevron is implicit — we don't render one because the tile
//     itself isn't navigable until the user signs in.

struct SocialFeatureCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.bindrAccent) private var accent

    let icon: String
    let title: String
    let description: String
    let tint: Color

    init(
        icon: String,
        title: String,
        description: String,
        tint: Color
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: BindrSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.2 : 0.16))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: BindrRadius.md, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 0.5)
            }

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

        }
        .padding(.horizontal, BindrSpacing.md)
        .padding(.vertical, BindrSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
    }
}

// MARK: - Section header

/// Small all-caps caption used above hero blocks ("LIVE NOW", "WHAT YOU UNLOCK").
struct SocialSectionEyebrow: View {
    @Environment(\.bindrAccent) private var accent
    let title: String
    var accentDot: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if accentDot {
                Circle()
                    .fill(BindrPalette.ownedGreen)
                    .frame(width: 7, height: 7)
                    .overlay {
                        Circle()
                            .stroke(BindrPalette.ownedGreen.opacity(0.35), lineWidth: 4)
                            .blur(radius: 2)
                    }
            }
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(.secondary)
        }
    }
}
