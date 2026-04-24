import SwiftUI
import Observation

@Observable
@MainActor
final class ThemeSettings {
    enum AppAppearance: String, CaseIterable, Identifiable {
        case light
        case dark
        case system
        
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .light: return "Light"
            case .dark: return "Dark"
            case .system: return "System"
            }
        }
    }

    private let cloudSettings: CloudSettingsService
    private let accentColorKey = "user_accent_color_hex"
    private let appearanceKey = "user_app_appearance"
    
    var accentColorHex: String {
        didSet {
            cloudSettings.set(accentColorHex, forKey: accentColorKey)
        }
    }
    
    var appearance: AppAppearance {
        didSet {
            cloudSettings.set(appearance.rawValue, forKey: appearanceKey)
        }
    }
    
    var accentColor: Color {
        Color(hex: accentColorHex)
    }
    
    var colorScheme: ColorScheme? {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
    init(cloudSettings: CloudSettingsService) {
        self.cloudSettings = cloudSettings
        // Default to a premium blue/indigo
        self.accentColorHex = cloudSettings.string(forKey: accentColorKey) ?? "4f46e5"
        
        let savedAppearance = cloudSettings.string(forKey: appearanceKey) ?? AppAppearance.dark.rawValue
        self.appearance = AppAppearance(rawValue: savedAppearance) ?? .dark
    }
    
    static let presetColors = [
        "4f46e5", // Indigo (Default)
        "ef4444", // Red
        "f59e0b", // Amber
        "10b981", // Emerald
        "06b6d4", // Cyan
        "3b82f6", // Blue
        "8b5cf6", // Violet
        "ec4899", // Pink
        "71717a"  // Zinc
    ]
}
