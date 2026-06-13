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
            hasCompletedInitialAppBootstrap = false
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
}
