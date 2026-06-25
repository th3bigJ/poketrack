import SwiftUI

// MARK: - ThemeCustomizationSections
//
// Shared appearance, glow, and atmosphere controls used by ThemesView and onboarding.

struct ThemeCustomizationSections: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent

    var body: some View {
        VStack(spacing: BindrSpacing.xl) {
            appearanceCard
            glowCard
            backgroundStyleCard
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
            footer: "Choose an atmosphere for Bindr. Each style includes its own matched accent and adapts automatically to light and dark mode."
        ) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: BindrSpacing.sm), count: 2),
                spacing: BindrSpacing.sm
            ) {
                ForEach(ThemeSettings.BackgroundStyle.allCases) { style in
                    backgroundStyleButton(style)
                }
            }
        }
    }

    private func backgroundStyleButton(_ style: ThemeSettings.BackgroundStyle) -> some View {
        let isSelected = services.theme.backgroundStyle == style

        return Button {
            services.theme.backgroundStyle = style
            Haptics.lightImpact()
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.52)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 6) {
                    Image(systemName: style.symbolName)
                    Text(style.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background {
                backgroundStylePreview(style)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isSelected ? style.accentColor : Color.primary.opacity(0.10), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func backgroundStylePreview(_ style: ThemeSettings.BackgroundStyle) -> some View {
        switch style {
        case .classic:
            Color(uiColor: .systemBackground)
                .overlay {
                    LinearGradient(
                        colors: [Color.primary.opacity(0.03), style.accentColor.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        case .celestial:
            Image("CelestialBackground")
                .resizable()
                .scaledToFill()
        case .grass, .fire, .water, .electric, .psychic, .dark, .fairy, .steel, .dragon:
            LinearGradient(
                colors: style.atmosphereColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: style.symbolName)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
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
