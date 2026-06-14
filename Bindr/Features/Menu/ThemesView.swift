import SwiftUI

// MARK: - ThemesView
//
// Themes & appearance settings. Refactor brief:
//   * Appearance picker uses native `Picker(.segmented)` — same control
//     iOS Settings uses for "Appearance: Light / Dark / Automatic".
//   * Background Glow uses a stock `Toggle` (no oversized custom styling)
//     with the explainer text rendered as a proper footer below the row,
//     not floating outside the card.
//   * Accent color grid is a fixed 6-column layout with tight spacing so
//     the swatches read as a single geometric block.
//   * "Select a color that reflects your style." now lives **inside** the
//     accent card as a footer caption, eliminating the previously orphaned
//     floating line of subtext.

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
