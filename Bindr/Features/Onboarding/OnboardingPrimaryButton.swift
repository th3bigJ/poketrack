import SwiftUI

// MARK: - OnboardingPrimaryButton
//
// Shared CTA button used by every onboarding step. Centralising the
// style here means tightening typography/weights/shadows in one place
// applies across the whole flow.
//
// Visual contract (post-refactor):
//   * Centred label only — no trailing arrow icon. iOS HIG: action
//     buttons describe the action, not where the user is going.
//   * Semibold (.semibold) label weight — not .heavy / .black.
//   * Accent gradient retained as the primary CTA recognition cue;
//     this is consistent with primary actions everywhere else in Bindr.
//   * Optional `subtitle` rendered as small caption *below* the button
//     for cases like "£24.99 / yr · auto-renews" beneath "Subscribe".

struct OnboardingPrimaryButton: View {
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            guard !disabled, !isLoading else { return }
            Haptics.lightImpact()
            action()
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.45 : 0.25), radius: 18, x: 0, y: 8)
            .opacity(disabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
    }
}

// MARK: - OnboardingSecondaryLink

/// Inline "Not now" / "Maybe later" / "Skip" affordance. Pure text, no
/// chrome — anchors the bottom of the screen without competing with the
/// primary CTA.
struct OnboardingSecondaryLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.lightImpact()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, BindrSpacing.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - OnboardingFooterBar

/// Bottom "footer bar" that hosts the primary CTA + optional secondary
/// link, with a soft gradient fade so scroll content disappears behind
/// it rather than slamming into the button edge.
struct OnboardingFooterBar<Primary: View, Secondary: View>: View {
    @ViewBuilder var primary: () -> Primary
    @ViewBuilder var secondary: () -> Secondary

    init(
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary = { EmptyView() }
    ) {
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        VStack(spacing: BindrSpacing.xs) {
            primary()
                .padding(.horizontal, BindrSpacing.lg)

            secondary()
        }
        .padding(.top, BindrSpacing.md)
        .padding(.bottom, BindrSpacing.lg)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(uiColor: .systemBackground).opacity(0.7),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
