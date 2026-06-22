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

    enum BackgroundStyle: String, CaseIterable, Identifiable {
        case classic
        case celestial
        case grass
        case fire
        case water
        case electric
        case psychic
        case dark
        case fairy
        case steel

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .classic: return "Classic"
            case .celestial: return "Celestial"
            case .grass: return "Grass"
            case .fire: return "Fire"
            case .water: return "Water"
            case .electric: return "Electric"
            case .psychic: return "Psychic"
            case .dark: return "Dark"
            case .fairy: return "Fairy"
            case .steel: return "Steel"
            }
        }

        var symbolName: String {
            switch self {
            case .classic: return "circle.lefthalf.filled"
            case .celestial: return "sparkles"
            case .grass: return "leaf.fill"
            case .fire: return "flame.fill"
            case .water: return "drop.fill"
            case .electric: return "bolt.fill"
            case .psychic: return "eye.fill"
            case .dark: return "moon.stars.fill"
            case .fairy: return "wand.and.stars"
            case .steel: return "hexagon.fill"
            }
        }

        var atmosphereColors: [Color] {
            switch self {
            case .classic:
                return [Color(hex: "f8fafc"), Color(hex: "e2e8f0")]
            case .celestial:
                return [Color(hex: "38bdf8"), Color(hex: "a78bfa"), Color(hex: "f472b6")]
            case .grass:
                return [Color(hex: "16a34a"), Color(hex: "84cc16"), Color(hex: "0f766e")]
            case .fire:
                return [Color(hex: "dc2626"), Color(hex: "f97316"), Color(hex: "facc15")]
            case .water:
                return [Color(hex: "0284c7"), Color(hex: "22d3ee"), Color(hex: "2563eb")]
            case .electric:
                return [Color(hex: "facc15"), Color(hex: "f59e0b"), Color(hex: "7c3aed")]
            case .psychic:
                return [Color(hex: "7c3aed"), Color(hex: "db2777"), Color(hex: "4f46e5")]
            case .dark:
                return [Color(hex: "111827"), Color(hex: "312e81"), Color(hex: "7f1d1d")]
            case .fairy:
                return [Color(hex: "f472b6"), Color(hex: "c084fc"), Color(hex: "67e8f9")]
            case .steel:
                return [Color(hex: "475569"), Color(hex: "cbd5e1"), Color(hex: "0e7490")]
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

    static let auroraCalmThemeID = "aurora-calm"
    static let auroraCalmThemeAccentHex = "c0392b"
    static let auroraCalmColors = [
        Color(hex: "1e356d"),
        Color(hex: "6a225f"),
        Color(hex: "c0392b")
    ]
    static let auroraCalmGradient = LinearGradient(
        colors: auroraCalmColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let localDefaultsPrefix = "Bindr.theme."
    private let accentColorKey = "user_accent_color_hex"
    private let appearanceKey = "user_app_appearance"
    private let backgroundGlowKey = "user_background_glow_enabled"
    private let backgroundStyleKey = "user_background_style"

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

    var backgroundStyle: BackgroundStyle {
        didSet {
            Self.saveLocal(backgroundStyle.rawValue, forKey: backgroundStyleKey)
            AppPreferencesBackup.notifyDidChange()
        }
    }
    
    var accentColor: Color {
        if isLogoThemeSelected {
            return Color(hex: Self.logoThemeAccentHex)
        } else if isAuroraCalmThemeSelected {
            return Color(hex: Self.auroraCalmThemeAccentHex)
        } else {
            return Color(hex: accentColorHex)
        }
    }

    var secondaryAccentColor: Color {
        if isLogoThemeSelected {
            return Color(hex: "ec4899")
        } else if isAuroraCalmThemeSelected {
            return Color(hex: "c0392b")
        } else {
            return accentColor
        }
    }

    var isLogoThemeSelected: Bool {
        accentColorHex == Self.logoThemeID
    }

    var isAuroraCalmThemeSelected: Bool {
        accentColorHex == Self.auroraCalmThemeID
    }

    var isGradientThemeSelected: Bool {
        isLogoThemeSelected || isAuroraCalmThemeSelected
    }

    var activeGradientColors: [Color] {
        if isAuroraCalmThemeSelected {
            return Self.auroraCalmColors
        }
        return Self.logoThemeColors
    }

    var activeGradient: LinearGradient {
        if isAuroraCalmThemeSelected {
            return Self.auroraCalmGradient
        }
        return Self.logoThemeGradient
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

        let savedBackgroundStyle = Self.localString(forKey: backgroundStyleKey) ?? BackgroundStyle.classic.rawValue
        self.backgroundStyle = BackgroundStyle(rawValue: savedBackgroundStyle) ?? .classic

        Self.saveLocal(accentColorHex, forKey: accentColorKey)
        Self.saveLocal(appearance.rawValue, forKey: appearanceKey)
        Self.saveLocal(backgroundGlowEnabled, forKey: backgroundGlowKey)
        Self.saveLocal(backgroundStyle.rawValue, forKey: backgroundStyleKey)

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
        if let raw = Self.localString(forKey: backgroundStyleKey),
           let parsed = BackgroundStyle(rawValue: raw),
           parsed != backgroundStyle {
            backgroundStyle = parsed
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

    static let avatarBackgroundColors = presetColors + [
        "22c55e", // Green
        "84cc16", // Lime
        "eab308", // Yellow
        "f97316", // Orange
        "14b8a6", // Teal
        "0ea5e9", // Sky
        "a855f7", // Purple
        "d946ef", // Fuchsia
        "f43f5e", // Rose
        "78716c", // Stone
        "475569", // Slate
        "1e3a5f", // Navy
        "be123c", // Crimson
        "65a30d", // Olive
        "0891b2", // Deep Cyan
    ]

    static let accentThemeOptions = [logoThemeID, auroraCalmThemeID] + presetColors

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
