import SwiftUI
import UIKit

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
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: BindrSpacing.xl) {
                appearanceCard
                glowCard
                accentCard
            }
            .padding(BindrSpacing.lg)
            .padding(.bottom, BindrSpacing.xxxl)
        }
        .background(BindrPageBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            themesHeader
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        cardSection(
            title: "Appearance",
            footer: "Choose how Bindr looks on your device."
        ) {
            Picker(
                "Appearance",
                selection: Bindable(services.theme).appearance
            ) {
                ForEach(ThemeSettings.AppAppearance.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Glow

    private var glowCard: some View {
        cardSection(
            title: nil,
            footer: "Adds a subtle color tint to the app background."
        ) {
            Toggle(isOn: Bindable(services.theme).backgroundGlowEnabled) {
                Text("Background Glow")
                    .font(.system(size: 15, weight: .semibold))
            }
            .tint(services.theme.accentColor)
            .onChange(of: services.theme.backgroundGlowEnabled) {
                Haptics.lightImpact()
            }
        }
    }

    // MARK: Accent

    private var accentCard: some View {
        cardSection(
            title: "Accent Color",
            footer: "Used for buttons, links, highlights, and the app background glow. Select a theme that reflects your style."
        ) {
            // Fixed-6 grid keeps the swatches geometric rather than
            // sprawling — adaptive sizing wraps unpredictably on the
            // notch widths we ship for.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: BindrSpacing.sm), count: 6),
                spacing: BindrSpacing.sm
            ) {
                ForEach(ThemeSettings.accentThemeOptions, id: \.self) { hex in
                    ColorSwatch(
                        hex: hex,
                        isSelected: normalizedAccentHex == normalizeHex(hex)
                    ) {
                        services.theme.accentColorHex = hex
                        Haptics.lightImpact()
                    }
                }

                ColorPickerSwatch(
                    selection: customAccentBinding,
                    isSelected: isUsingCustomAccent
                )
            }
        }
    }

    private var normalizedAccentHex: String {
        normalizeHex(services.theme.accentColorHex)
    }

    private var isUsingCustomAccent: Bool {
        !ThemeSettings.accentThemeOptions.contains(where: { normalizeHex($0) == normalizedAccentHex })
    }

    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { services.theme.accentColor },
            set: { newColor in
                services.theme.accentColorHex = hexString(from: newColor)
            }
        )
    }

    private func normalizeHex(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased()
    }

    private func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return services.theme.accentColorHex
        }

        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        return String(format: "%02x%02x%02x", r, g, b)
    }

    // MARK: Section helper

    /// Reusable "card with optional title and inline footer". The footer
    /// sits *inside* the card so loose instructional text never floats
    /// underneath the rounded container.
    @ViewBuilder
    private func cardSection<Content: View>(
        title: String?,
        footer: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: BindrSpacing.md) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }

            content()

            Text(footer)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(BindrSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCardStyle(cornerRadius: BindrRadius.xl, interactive: false)
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

// MARK: - Color swatch
//
// Compact accent swatch: solid circle, no shadow, no white outer ring.
// Selection state is a subtle inner check + accent-tinted ring so the
// swatch reads as a single dense token in the grid rather than each
// being a freestanding chip.
private struct ColorSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    private var isLogoTheme: Bool {
        hex == ThemeSettings.logoThemeID
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                swatchFill
                    .frame(width: 36, height: 36)

                if isSelected {
                    Circle()
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.92 : 1.0), lineWidth: 2)
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLogoTheme ? "Bindr logo theme" : "Accent color \(hex)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var swatchFill: some View {
        if isLogoTheme {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "22d3ee"),
                            Color(hex: "6366f1"),
                            Color(hex: "ec4899")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.48), lineWidth: 1)
                }
        } else {
            Circle()
                .fill(Color(hex: hex))
        }
    }
}

private struct ColorPickerSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: Color
    let isSelected: Bool

    var body: some View {
        ColorPicker("Custom accent color", selection: $selection, supportsOpacity: false)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay {
                ZStack {
                    Circle()
                        .fill(selection)
                        .frame(width: 36, height: 36)

                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)

                    if isSelected {
                        Circle()
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.92 : 1.0), lineWidth: 2)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel("Custom accent color")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
