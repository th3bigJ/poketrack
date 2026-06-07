import Foundation
import Observation

/// Tracks onboarding and bootstrap completion state. Pokemon is the only supported brand.
@Observable
@MainActor
final class BrandSettings {
    private static let onboardingKey = "tcg_brand_onboarding_completed"
    private static let initialAppBootstrapKey = "tcg_initial_app_bootstrap_completed"

    let enabledBrands: Set<TCGBrand> = [.pokemon]
    let selectedCatalogBrand: TCGBrand = .pokemon

    var hasCompletedBrandOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedBrandOnboarding, forKey: Self.onboardingKey) }
    }

    var hasCompletedInitialAppBootstrap: Bool {
        didSet { UserDefaults.standard.set(hasCompletedInitialAppBootstrap, forKey: Self.initialAppBootstrapKey) }
    }

    init() {
        let defaults = UserDefaults.standard

        let onboarding = defaults.object(forKey: Self.onboardingKey) != nil
            ? defaults.bool(forKey: Self.onboardingKey)
            : false
        hasCompletedBrandOnboarding = onboarding

        if defaults.object(forKey: Self.initialAppBootstrapKey) != nil {
            hasCompletedInitialAppBootstrap = defaults.bool(forKey: Self.initialAppBootstrapKey)
        } else {
            let bootstrap = onboarding && Self.hasExistingCatalogDatabaseFile()
            hasCompletedInitialAppBootstrap = bootstrap
            if bootstrap {
                defaults.set(true, forKey: Self.initialAppBootstrapKey)
            }
        }
    }

    func markInitialAppBootstrapCompleted() {
        hasCompletedInitialAppBootstrap = true
    }

    func completeBrandOnboarding() {
        hasCompletedBrandOnboarding = true
    }

    func setEnabled(_ brand: TCGBrand, isOn: Bool) {
        // No-op: only Pokemon is supported.
    }

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
}
