import Foundation
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
    static let logoThemeID = "bindr-logo"
    static let logoThemeAccentHex = "8b5cf6"
    static let logoThemeColors = [
        Color(hex: "22d3ee"),
        Color(hex: "6366f1"),
        Color(hex: "8b5cf6"),
        Color(hex: "ec4899")
    ]
    static let logoThemeGradient = LinearGradient(
        colors: logoThemeColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    private static let localDefaultsPrefix = "Bindr.theme."
    private let accentColorKey = "user_accent_color_hex"
    private let appearanceKey = "user_app_appearance"
    private let backgroundGlowKey = "user_background_glow_enabled"
    private var acceptsFirstCloudThemeRefresh = false

    var accentColorHex: String {
        didSet {
            acceptsFirstCloudThemeRefresh = false
            Self.saveLocal(accentColorHex, forKey: accentColorKey)
            cloudSettings.set(accentColorHex, forKey: accentColorKey)
        }
    }

    var appearance: AppAppearance {
        didSet {
            Self.saveLocal(appearance.rawValue, forKey: appearanceKey)
            cloudSettings.set(appearance.rawValue, forKey: appearanceKey)
        }
    }

    var backgroundGlowEnabled: Bool {
        didSet {
            Self.saveLocal(backgroundGlowEnabled, forKey: backgroundGlowKey)
            cloudSettings.set(backgroundGlowEnabled, forKey: backgroundGlowKey)
        }
    }
    
    var accentColor: Color {
        isLogoThemeSelected ? Color(hex: Self.logoThemeAccentHex) : Color(hex: accentColorHex)
    }

    var isLogoThemeSelected: Bool {
        accentColorHex == Self.logoThemeID
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

        let localAccent = Self.localString(forKey: accentColorKey)
        let localAppearance = Self.localString(forKey: appearanceKey)
        let localGlow = Self.localBool(forKey: backgroundGlowKey)
        self.acceptsFirstCloudThemeRefresh = localAccent == nil

        // Default to a premium blue/indigo
        self.accentColorHex = localAccent
            ?? cloudSettings.string(forKey: accentColorKey)
            ?? "4f46e5"

        let savedAppearance = localAppearance
            ?? cloudSettings.string(forKey: appearanceKey)
            ?? AppAppearance.system.rawValue
        self.appearance = AppAppearance(rawValue: savedAppearance) ?? .system

        if let localGlow {
            self.backgroundGlowEnabled = localGlow
        } else if cloudSettings.hasValue(forKey: backgroundGlowKey) {
            self.backgroundGlowEnabled = cloudSettings.bool(forKey: backgroundGlowKey)
        } else {
            self.backgroundGlowEnabled = true
        }

        Self.saveLocal(accentColorHex, forKey: accentColorKey)
        Self.saveLocal(appearance.rawValue, forKey: appearanceKey)
        Self.saveLocal(backgroundGlowEnabled, forKey: backgroundGlowKey)

        NotificationCenter.default.addObserver(
            forName: .cloudSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.acceptsFirstCloudThemeRefresh else { return }
                guard let cloudAccent = self.cloudSettings.string(forKey: self.accentColorKey) else { return }
                self.acceptsFirstCloudThemeRefresh = false
                if self.accentColorHex != cloudAccent {
                    self.accentColorHex = cloudAccent
                }
            }
        }
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

    static let accentThemeOptions = [logoThemeID] + presetColors

    private static func localKey(_ key: String) -> String {
        localDefaultsPrefix + key
    }

    private static func saveLocal(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: localKey(key))
    }

    private static func saveLocal(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: localKey(key))
    }

    private static func localString(forKey key: String) -> String? {
        UserDefaults.standard.string(forKey: localKey(key))
    }

    private static func localBool(forKey key: String) -> Bool? {
        guard UserDefaults.standard.object(forKey: localKey(key)) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: localKey(key))
    }
}
