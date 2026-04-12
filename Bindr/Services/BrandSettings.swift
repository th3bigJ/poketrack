import Foundation
import Observation

/// User-selected TCG brands (browse catalog + sync scope later) and the active browse brand.
@Observable
@MainActor
final class BrandSettings {
    private static let enabledBrandsKey = "tcg_brand_enabled_raw_values"
    private static let selectedBrandKey = "tcg_brand_selected_raw"
    private static let onboardingKey = "tcg_brand_onboarding_completed"
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

    init() {
        let defaults = UserDefaults.standard
        let hasSavedBrands = defaults.object(forKey: Self.enabledBrandsKey) != nil

        var enabled: Set<TCGBrand>
        var selected: TCGBrand
        var onboarding: Bool

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
                onboarding = true
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
        } else {
            // First run of brand settings: distinguish upgrading users vs a fresh install.
            enabled = [.pokemon]
            selected = .pokemon
            if Self.hasLikelyExistingUserData() {
                // Already had catalog / collection data before multi-brand: Pokémon only, ONE PIECE opt-in from Account.
                onboarding = true
            } else {
                // True first install: show brand picker; ONE PIECE off until the user enables it.
                onboarding = false
            }
            Self.persistInitialState(
                defaults: defaults,
                enabled: enabled,
                selected: selected,
                onboarding: onboarding
            )
        }

        enabledBrands = enabled
        selectedCatalogBrand = selected
        hasCompletedBrandOnboarding = onboarding
    }

    /// Prior data on disk means this is an app update / existing library, not a brand-new install.
    private static func hasLikelyExistingUserData() -> Bool {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        let dir = appSupport.appendingPathComponent("Bindr", isDirectory: true)
        let candidates = [
            dir.appendingPathComponent("catalog.sqlite"),
            dir.appendingPathComponent("Bindr.store"),
        ]
        for url in candidates {
            guard fm.fileExists(atPath: url.path) else { continue }
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? UInt64,
                  size > 0 else { continue }
            return true
        }
        return false
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
