import SwiftUI

// MARK: - OnboardingThemeView
//
// Step 2. Theme atmosphere — first screen after Welcome.
// Reuses `ThemeCustomizationSections` so choices match Account → Themes.

struct OnboardingThemeView: View {
    @Environment(AppServices.self) private var services

    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BindrSpacing.xl) {
                    OnboardingHeadline(
                        title: "Make it\nyours.",
                        subtitle: "Choose light or dark mode, set your atmosphere and glow, and Bindr will match the accent for you."
                    )

                    ThemeCustomizationSections()

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.xl)
            }
            .scrollIndicators(.hidden)

            OnboardingFooterBar(
                primary: {
                    OnboardingPrimaryButton(title: "Continue", action: onContinue)
                },
                secondary: {
                    OnboardingSecondaryLink(title: "Not now", action: onSkip)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bindrTheme(accent: services.theme.accentColor)
    }
}
