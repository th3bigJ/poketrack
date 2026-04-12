import Foundation
import Observation

/// User-selected TCG brands (browse catalog + sync scope later) and the active browse brand.
@Observable
@MainActor
final class BrandSettings {
    private static let enabledBrandsKey = "tcg_brand_enabled_raw_values"
    private static let selectedBrandKey = "tcg_brand_selected_raw"
    private static let onboardingKey = "tcg_brand_onboarding_completed"
    /// After the first successful blocking catalog bootstrap, subsequent launches refresh in the background without a full-screen gate.
    private static let initialAppBootstrapKey = "tcg_initial_app_bootstrap_completed"
    /// One-time: older builds saved Pokémon + ONE PIECE without an onboarding flag; drop OP so existing users opt in.
    private static let legacyDefaultOnePieceClearedKey = "tcg_brand_legacy_default_onepiece_cleared"

    var enabledBrands: Set<TCGBrand> {
        didSet {
            normalizeSelectionAfterEnabledChange()
            persist()
        }
    }

    /// Browse tab / card grid uses this catalog.
    var selectedCatalogBrand: TCGBrand {
        didSet {
            if !enabledBrands.contains(selectedCatalogBrand) {
                selectedCatalogBrand = enabledBrands.sorted(by: { $0.menuOrder < $1.menuOrder }).first ?? .pokemon
            }
            persist()
        }
    }

    var hasCompletedBrandOnboarding: Bool {
        didSet { persist() }
    }

    /// True after the first full catalog bootstrap has finished (blocking UI). Persisted; used to skip the launch gate on later opens.
    var hasCompletedInitialAppBootstrap: Bool {
        didSet { persist() }
    }

    init() {
        let defaults = UserDefaults.standard
        let hasSavedBrands = defaults.object(forKey: Self.enabledBrandsKey) != nil

        var enabled: Set<TCGBrand>
        var selected: TCGBrand
        var onboarding: Bool
        var initialAppBootstrapComplete: Bool

        if hasSavedBrands,
           let raw = defaults.array(forKey: Self.enabledBrandsKey) as? [String],
           !raw.isEmpty {
            enabled = Set(raw.compactMap(TCGBrand.init(rawValue:)))
            if enabled.isEmpty { enabled = [.pokemon] }

            if let sel = defaults.string(forKey: Self.selectedBrandKey),
               let b = TCGBrand(rawValue: sel),
               enabled.contains(b) {
                selected = b
            } else {
                selected = enabled.sorted(by: { $0.menuOrder < $1.menuOrder }).first ?? .pokemon
            }
            if defaults.object(forKey: Self.onboardingKey) != nil {
                onboarding = defaults.bool(forKey: Self.onboardingKey)
            } else {
                // No explicit flag yet — show the brand picker once (legacy installs included).
                onboarding = false
            }

            if !defaults.bool(forKey: Self.legacyDefaultOnePieceClearedKey),
               enabled == [.pokemon, .onePiece],
               defaults.object(forKey: Self.onboardingKey) == nil {
                enabled = [.pokemon]
                selected = .pokemon
                onboarding = true
                defaults.set(true, forKey: Self.legacyDefaultOnePieceClearedKey)
                Self.persistInitialState(
                    defaults: defaults,
                    enabled: enabled,
                    selected: selected,
                    onboarding: onboarding
                )
            }

            if defaults.object(forKey: Self.initialAppBootstrapKey) != nil {
                initialAppBootstrapComplete = defaults.bool(forKey: Self.initialAppBootstrapKey)
            } else {
                // New installs: false. Upgrades: if they already finished onboarding and have a local catalog DB, skip the one-time blocking gate.
                initialAppBootstrapComplete = onboarding && Self.hasExistingCatalogDatabaseFile()
                if initialAppBootstrapComplete {
                    defaults.set(true, forKey: Self.initialAppBootstrapKey)
                }
            }
        } else {
            // First time we persist brand settings (no `enabledBrands` key yet).
            enabled = [.pokemon]
            selected = .pokemon
            if defaults.object(forKey: Self.onboardingKey) != nil {
                onboarding = defaults.bool(forKey: Self.onboardingKey)
            } else {
                // Show brand picker until the user taps Continue (do not skip just because catalog data exists).
                onboarding = false
            }
            Self.persistInitialState(
                defaults: defaults,
                enabled: enabled,
                selected: selected,
                onboarding: onboarding
            )

            if defaults.object(forKey: Self.initialAppBootstrapKey) != nil {
                initialAppBootstrapComplete = defaults.bool(forKey: Self.initialAppBootstrapKey)
            } else {
                initialAppBootstrapComplete = onboarding && Self.hasExistingCatalogDatabaseFile()
                if initialAppBootstrapComplete {
                    defaults.set(true, forKey: Self.initialAppBootstrapKey)
                }
            }
        }

        enabledBrands = enabled
        selectedCatalogBrand = selected
        hasCompletedBrandOnboarding = onboarding
        hasCompletedInitialAppBootstrap = initialAppBootstrapComplete
    }

    /// Call when the first blocking ``AppServices/bootstrap()`` completes successfully.
    func markInitialAppBootstrapCompleted() {
        hasCompletedInitialAppBootstrap = true
    }

    /// `Application Support/Bindr/catalog.sqlite` with non-trivial size — used to migrate pre–feature users onto background refresh.
    private static func hasExistingCatalogDatabaseFile() -> Bool {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return false }
        let path = base.appendingPathComponent("Bindr/catalog.sqlite", isDirectory: false).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber
        else { return false }
        return size.int64Value > 8_192
    }

    private static func persistInitialState(
        defaults: UserDefaults,
        enabled: Set<TCGBrand>,
        selected: TCGBrand,
        onboarding: Bool
    ) {
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: enabledBrandsKey)
        defaults.set(selected.rawValue, forKey: selectedBrandKey)
        defaults.set(onboarding, forKey: onboardingKey)
    }

    private func normalizeSelectionAfterEnabledChange() {
        if enabledBrands.isEmpty {
            enabledBrands = [.pokemon]
        }
        if !enabledBrands.contains(selectedCatalogBrand) {
            selectedCatalogBrand = enabledBrands.sorted(by: { $0.menuOrder < $1.menuOrder }).first ?? .pokemon
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(enabledBrands.map(\.rawValue).sorted(), forKey: Self.enabledBrandsKey)
        defaults.set(selectedCatalogBrand.rawValue, forKey: Self.selectedBrandKey)
        defaults.set(hasCompletedBrandOnboarding, forKey: Self.onboardingKey)
        defaults.set(hasCompletedInitialAppBootstrap, forKey: Self.initialAppBootstrapKey)
    }

    func setEnabled(_ brand: TCGBrand, isOn: Bool) {
        if isOn {
            enabledBrands.insert(brand)
        } else {
            enabledBrands.remove(brand)
        }
    }

    func completeBrandOnboarding() {
        hasCompletedBrandOnboarding = true
    }
}
