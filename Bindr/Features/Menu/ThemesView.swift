import SwiftUI

struct ThemesView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
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
                .padding(.vertical, 4)
            }
            
            Section {
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
                .padding(.vertical, 4)
            } footer: {
                Text("Select a color that reflects your style.")
            }
        }
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
