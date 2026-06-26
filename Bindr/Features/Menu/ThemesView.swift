import SwiftUI

// MARK: - ThemesView
//
// Themes & appearance settings. Refactor brief:
//   * Appearance picker uses `SlidingSegmentedPicker` (pill-label tabs).
//   * Background styles own their matched tint colors in a 3-column grid.

struct ThemesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            ThemeCustomizationSections()
                .padding(.horizontal, BindrSpacing.lg)
                .padding(.top, BindrSpacing.sm)
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
