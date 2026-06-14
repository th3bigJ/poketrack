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

    var accentColorHex: String {
        didSet {
            Self.saveLocal(accentColorHex, forKey: accentColorKey)
            AppPreferencesBackup.notifyDidChange()
        }
    }

    var appearance: AppAppearance {
        didSet {
            Self.saveLocal(appearance.rawValue, forKey: appearanceKey)
            AppPreferencesBackup.notifyDidChange()
        }
    }

    var backgroundGlowEnabled: Bool {
        didSet {
            Self.saveLocal(backgroundGlowEnabled, forKey: backgroundGlowKey)
            AppPreferencesBackup.notifyDidChange()
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
    
    init() {
        self.accentColorHex = Self.localString(forKey: accentColorKey) ?? "4f46e5"

        let savedAppearance = Self.localString(forKey: appearanceKey) ?? AppAppearance.system.rawValue
        self.appearance = AppAppearance(rawValue: savedAppearance) ?? .system

        if let localGlow = Self.localBool(forKey: backgroundGlowKey) {
            self.backgroundGlowEnabled = localGlow
        } else {
            self.backgroundGlowEnabled = true
        }

        Self.saveLocal(accentColorHex, forKey: accentColorKey)
        Self.saveLocal(appearance.rawValue, forKey: appearanceKey)
        Self.saveLocal(backgroundGlowEnabled, forKey: backgroundGlowKey)

        NotificationCenter.default.addObserver(
            forName: .appPreferencesDidRestore,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromUserDefaults()
            }
        }
    }

    func reloadFromUserDefaults() {
        if let accent = Self.localString(forKey: accentColorKey), accent != accentColorHex {
            accentColorHex = accent
        }
        if let raw = Self.localString(forKey: appearanceKey),
           let parsed = AppAppearance(rawValue: raw),
           parsed != appearance {
            appearance = parsed
        }
        if let glow = Self.localBool(forKey: backgroundGlowKey), glow != backgroundGlowEnabled {
            backgroundGlowEnabled = glow
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
