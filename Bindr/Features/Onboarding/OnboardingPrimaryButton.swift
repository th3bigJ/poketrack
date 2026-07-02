import SwiftUI

// MARK: - OnboardingPrimaryButton
//
// Shared CTA button used by every onboarding step. Refactored to use a
// premium, tactile ButtonStyle that automatically animates a scale compression
// when pressed—matching standard premium native iOS button animations.
//
// Visual contract:
//   * Centred label only — no trailing arrow icon.
//   * Semibold (.semibold) label weight.
//   * Dynamic scaling feedback upon press.
//   * Unified brand color gradient backdrop with native drop shadow.

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
                }
            }
        }
        .buttonStyle(TactileBrandButtonStyle(disabled: disabled || isLoading))
        .disabled(disabled || isLoading)
    }
}

// MARK: - TactileBrandButtonStyle

struct TactileBrandButtonStyle: ButtonStyle {
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services
    let disabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let usesGradient = services.theme.isGradientThemeSelected
        let labelColor = usesGradient ? Color.white : accent.bindrLabelOnFill(in: colorScheme)

        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                    .bindrAccentFill(accent, logoOpacity: 0.96)
            }
            .shadow(color: accent.opacity(colorScheme == .dark ? 0.35 : 0.18), radius: 12, x: 0, y: 6)
            .opacity(disabled ? 0.5 : (configuration.isPressed ? 0.90 : 1.0))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
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
                .contentShape(Rectangle())
        }
        .buttonStyle(SecondaryLinkButtonStyle())
    }
}

struct SecondaryLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            OnboardingStickyFooterBackground()
        }
    }
}
