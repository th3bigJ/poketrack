import SwiftUI
import UIKit

// MARK: - ThemeCustomizationSections
//
// Shared appearance, glow, and accent controls used by ThemesView and onboarding.

struct ThemeCustomizationSections: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent

    var body: some View {
        VStack(spacing: BindrSpacing.xl) {
            appearanceCard
            glowCard
            backgroundStyleCard
            accentCard
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        themeCardSection(
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
        themeCardSection(
            title: nil,
            footer: "Adds a subtle color tint to the app background."
        ) {
            Toggle(isOn: Bindable(services.theme).backgroundGlowEnabled) {
                Text("Background Glow")
                    .font(.system(size: 15, weight: .semibold))
            }
            .tint(accent)
            .onChange(of: services.theme.backgroundGlowEnabled) {
                Haptics.lightImpact()
            }
        }
    }

    // MARK: Background style

    private var backgroundStyleCard: some View {
        themeCardSection(
            title: "Background Style",
            footer: "Choose the atmosphere used across Bindr. Celestial adapts automatically for light and dark mode."
        ) {
            Picker(
                "Background Style",
                selection: Bindable(services.theme).backgroundStyle
            ) {
                ForEach(ThemeSettings.BackgroundStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: services.theme.backgroundStyle) {
                Haptics.lightImpact()
            }

            backgroundStylePreview
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var backgroundStylePreview: some View {
        switch services.theme.backgroundStyle {
        case .classic:
            BindrPageBackground()
        case .celestial:
            Image("CelestialBackground")
                .resizable()
                .scaledToFill()
        }
    }

    // MARK: Accent

    private var accentCard: some View {
        themeCardSection(
            title: "Accent Color",
            footer: "Used for buttons, links, highlights, and the app background glow. Select a theme that reflects your style."
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: BindrSpacing.sm), count: 6),
                spacing: BindrSpacing.sm
            ) {
                ForEach(ThemeSettings.accentThemeOptions, id: \.self) { hex in
                    ThemeColorSwatch(
                        hex: hex,
                        isSelected: normalizedAccentHex == normalizeHex(hex)
                    ) {
                        services.theme.accentColorHex = hex
                        Haptics.lightImpact()
                    }
                }

                ThemeColorPickerSwatch(
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

    @ViewBuilder
    private func themeCardSection<Content: View>(
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
}

// MARK: - Color swatch

struct ThemeColorSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    private var isLogoTheme: Bool {
        hex == ThemeSettings.logoThemeID
    }

    private var isAuroraCalmTheme: Bool {
        hex == ThemeSettings.auroraCalmThemeID
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
        .accessibilityLabel(isLogoTheme ? "Bindr logo theme" : isAuroraCalmTheme ? "Aurora Calm theme" : "Accent color \(hex)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var swatchFill: some View {
        if isLogoTheme {
            Circle()
                .fill(ThemeSettings.logoThemeGradient)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.48), lineWidth: 1)
                }
        } else if isAuroraCalmTheme {
            Circle()
                .fill(ThemeSettings.auroraCalmGradient)
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

struct ThemeColorPickerSwatch: View {
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
