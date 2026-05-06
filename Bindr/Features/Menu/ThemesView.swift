import SwiftUI

struct ThemesView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Appearance Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Appearance")
                        .font(.headline)
                    
                    Text("Choose how Bindr looks on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    SlidingSegmentedPicker(
                        selection: Bindable(services.theme).appearance,
                        items: ThemeSettings.AppAppearance.allCases,
                        title: { $0.displayName }
                    )
                    .padding(.vertical, 8)
                }
                .padding(16)
                .glassCardStyle(cornerRadius: 16, interactive: false)
                
                // Background Glow Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Bindable(services.theme).backgroundGlowEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Background Glow")
                                .font(.body.weight(.bold))
                            Text("Adds a subtle color tint to the app background.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: services.theme.backgroundGlowEnabled) {
                        Haptics.lightImpact()
                    }
                }
                .padding(16)
                .glassCardStyle(cornerRadius: 16, interactive: false)

                // Accent Color Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent Color")
                        .font(.headline)
                    
                    Text("Choose a color that will be used for buttons, links, and highlights throughout the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 16) {
                        ForEach(ThemeSettings.presetColors, id: \.self) { hex in
                            ColorPill(hex: hex, isSelected: services.theme.accentColorHex == hex) {
                                services.theme.accentColorHex = hex
                                Haptics.lightImpact()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(16)
                .glassCardStyle(cornerRadius: 16, interactive: false)
                .overlay(alignment: .bottomLeading) {
                    Text("Select a color that reflects your style.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                        .offset(y: 20)
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(BindrPageBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            themesHeader
        }
    }

    private var themesHeader: some View {
        ZStack {
            Text("Themes")
                .font(.title2.weight(.bold))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct ColorPill: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 44, height: 44)
                
                if isSelected {
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
