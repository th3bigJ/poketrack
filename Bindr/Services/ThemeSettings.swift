import SwiftUI
import Observation

@Observable
@MainActor
final class ThemeSettings {
    private let cloudSettings: CloudSettingsService
    private let accentColorKey = "user_accent_color_hex"
    
    var accentColorHex: String {
        didSet {
            cloudSettings.set(accentColorHex, forKey: accentColorKey)
        }
    }
    
    var accentColor: Color {
        Color(hex: accentColorHex)
    }
    
    init(cloudSettings: CloudSettingsService) {
        self.cloudSettings = cloudSettings
        // Default to a premium blue/indigo
        self.accentColorHex = cloudSettings.string(forKey: accentColorKey) ?? "4f46e5"
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
