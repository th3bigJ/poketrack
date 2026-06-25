import SwiftUI

// MARK: - ThemesView
//
// Themes & appearance settings. Refactor brief:
//   * Appearance picker uses native `Picker(.segmented)` — same control
//     iOS Settings uses for "Appearance: Light / Dark / Automatic".
//   * Background Glow uses a stock `Toggle` (no oversized custom styling)
//     with the explainer text rendered as a proper footer below the row,
//     not floating outside the card.
//   * Background styles now own their matched tint colors, so the UI presents
//     one atmosphere choice instead of separate color controls.

struct ThemesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            ThemeCustomizationSections()
                .padding(BindrSpacing.lg)
                .padding(.bottom, BindrSpacing.xxxl)
        }
        .background(BindrPageBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            themesHeader
        }
    }

    // MARK: Header

    private var themesHeader: some View {
        ZStack {
            Text("Themes")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            HStack {
                ChromeGlassCircleButton(accessibilityLabel: "Back") {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, BindrSpacing.lg)
        .padding(.vertical, BindrSpacing.sm)
    }
}
