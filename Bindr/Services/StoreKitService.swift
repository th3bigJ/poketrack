import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class StoreKitService {
    private static let premiumEntitlementDefaultsKey = "Bindr.store.premiumEntitlement"
    /// Set after the user explicitly subscribes or taps Restore Purchases — blocks silent
    /// entitlement sync on fresh installs until then.
    private static let explicitActivationCompleteKey = "Bindr.store.premiumExplicitActivationComplete"

    /// Raw entitlement from StoreKit (before DEBUG overrides).
    private var premiumEntitlement = false
    private(set) var isCheckingEntitlements = false

    /// Fresh installs stay free until the user purchases or restores — not from launch-time StoreKit sync.
    private var requiresExplicitPremiumActivation: Bool {
        !UserDefaults.standard.bool(forKey: Self.explicitActivationCompleteKey)
    }

    /// Effective premium flag for the app. In **Debug** builds, use **Force free tier** on Account to test without Premium.
    var isPremium: Bool {
        #if DEBUG
        if debugForceFreeTier { return false }
        #endif
        return premiumEntitlement
    }

    private(set) var products: [Product] = []
    private(set) var annualProduct: Product?
    /// App Store storefront country (e.g. `GBR`) — drives placeholder currency when products are still loading.
    private(set) var storefrontCountryCode: String?
    private(set) var purchaseError: String?
    private(set) var isRestoring = false
    private(set) var restoreMessage: String?

    /// TestFlight builds bill through Apple's sandbox — testers must sign in under Settings → App Store → Sandbox Account.
    var requiresSandboxAccount: Bool {
        AppDistribution.requiresSandboxIAP
    }

    var hasPurchaseOptions: Bool {
        !products.isEmpty
    }

    /// Localized plan prices for paywalls — always matches the App Store storefront currency.
    var subscriptionPricing: PremiumSubscriptionPricing {
        PremiumSubscriptionPricing(
            monthlyProduct: products.first,
            annualProduct: annualProduct,
            storefrontCountryCode: storefrontCountryCode
        )
    }

    private var updatesTask: Task<Void, Never>?
    /// Drops stale entitlement fetches when the user restores while launch sync is still running.
    private var entitlementFetchGeneration = 0

    #if DEBUG
    static let forceFreeTierDefaultsKey = "Bindr.debug.forceFreeTier"
    /// When `true`, the app behaves as non‑Premium for testing; StoreKit entitlements are unchanged.
    var debugForceFreeTier = false {
        didSet { UserDefaults.standard.set(debugForceFreeTier, forKey: Self.forceFreeTierDefaultsKey) }
    }
    #endif

    init() {
        // Always start non‑Premium until StoreKit confirms an active subscription.
        // A cached UserDefaults flag (from Xcode debug, an old TestFlight test, or a
        // race before checkEntitlements finishes) must not unlock Premium or skip
        // onboarding — that cache is written by setPremiumEntitlement but never read here.
        premiumEntitlement = false
        migrateExplicitActivationIfNeeded()
        #if DEBUG
        debugForceFreeTier = UserDefaults.standard.bool(forKey: Self.forceFreeTierDefaultsKey)
        #endif
        updatesTask = Task { await observeTransactions() }
        Task {
            if let storefront = await Storefront.current {
                storefrontCountryCode = storefront.countryCode
            }
            await finishUnfinishedTransactions()
            // Fresh installs must activate via Subscribe or Restore — a background
            // entitlement pass here can race the user's restore and look like a no-op.
            if !requiresExplicitPremiumActivation {
                await checkEntitlements()
            }
        }
    }

    /// Grandfather existing Premium subscribers upgrading to this build; fresh installs stay gated.
    private func migrateExplicitActivationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.explicitActivationCompleteKey) else { return }
        if UserDefaults.standard.bool(forKey: Self.premiumEntitlementDefaultsKey) {
            UserDefaults.standard.set(true, forKey: Self.explicitActivationCompleteKey)
        }
    }

    func loadProducts() async {
        if let storefront = await Storefront.current {
            storefrontCountryCode = storefront.countryCode
        }

        // Fetch from App Store off @MainActor — network latency must not block the main thread.
        do {
            let fetched = try await Task.detached(priority: .utility) {
                try await Product.products(for: [
                    AppConfiguration.premiumProductID,
                    AppConfiguration.premiumAnnualProductID
                ])
            }.value
            products = fetched.filter { $0.id == AppConfiguration.premiumProductID }
            annualProduct = fetched.first { $0.id == AppConfiguration.premiumAnnualProductID }
            purchaseError = nil
        } catch {
            purchaseError = Self.userFacingMessage(for: error, testFlight: requiresSandboxAccount)
            products = []
            annualProduct = nil
        }
    }

    func checkEntitlements() async {
        guard !isCheckingEntitlements else { return }
        await fetchAndApplyEntitlements(fromExplicitUserAction: false)
    }

    /// Always re-reads StoreKit entitlements. Used by restore so a concurrent launch-time
    /// entitlement check cannot cause the refresh to be skipped.
    private func fetchAndApplyEntitlements(fromExplicitUserAction: Bool) async {
        entitlementFetchGeneration += 1
        let generation = entitlementFetchGeneration
        isCheckingEntitlements = true
        defer {
            if generation == entitlementFetchGeneration {
                isCheckingEntitlements = false
            }
        }

        // Drain the async sequence on a background executor so StoreKit's
        // network round-trip doesn't hold @MainActor while Apple's servers respond.
        let premium = await Task.detached(priority: .userInitiated) {
            var found = false
            for await result in StoreKit.Transaction.currentEntitlements {
                guard case .verified(let t) = result else { continue }
                guard Self.isPremiumProduct(t.productID) else { continue }
                guard Self.acceptsTransactionEnvironment(t.environment) else { continue }
                found = true
                break
            }
            return found
        }.value

        guard generation == entitlementFetchGeneration else { return }

        if premium {
            if requiresExplicitPremiumActivation && !fromExplicitUserAction {
                // Fresh install: keep free until Subscribe or Restore Purchases.
                setPremiumEntitlement(false)
                return
            }
            setPremiumEntitlement(true)
            if fromExplicitUserAction {
                markExplicitPremiumActivationComplete()
            }
        } else {
            setPremiumEntitlement(false)
        }
    }

    func purchase(annual: Bool = false) async throws {
        purchaseError = nil

        let product: Product?
        if annual {
            product = annualProduct ?? products.first
        } else {
            product = products.first
        }
        guard let product else {
            await loadProducts()
            throw PurchaseError.productUnavailable
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let t) = verification else { return }
                guard Self.isPremiumProduct(t.productID),
                      Self.acceptsTransactionEnvironment(t.environment) else { return }
                setPremiumEntitlement(true)
                markExplicitPremiumActivationComplete()
                await t.finish()
            case .userCancelled:
                break
            case .pending:
                break
            @unknown default:
                break
            }
        } catch {
            let message = Self.userFacingMessage(for: error, testFlight: requiresSandboxAccount)
            purchaseError = message
            throw PurchaseError.storeKit(message)
        }
    }

    func restore() async throws {
        purchaseError = nil
        restoreMessage = nil

        // Read entitlements from StoreKit's local cache — does not call AppStore.sync(),
        // so it avoids the system "Sign in to Apple Account" / password sheet.
        // StoreKit 2 keeps subscriptions available here for the signed-in store account.
        isRestoring = true
        defer { isRestoring = false }

        await fetchAndApplyEntitlements(fromExplicitUserAction: true)

        if premiumEntitlement {
            restoreMessage = nil
        } else {
            restoreMessage = requiresSandboxAccount
                ? "No active subscription was found on this device. Subscribe here, or sign into a Sandbox Apple ID under Settings → App Store → Sandbox Account if you purchased on another tester account."
                : "No active subscription was found for this Apple ID on this device."
        }
    }

    /// Clears any transactions left open by a crash or network drop so new purchases can proceed.
    private func finishUnfinishedTransactions() async {
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if Self.isPremiumProduct(transaction.productID),
               Self.acceptsTransactionEnvironment(transaction.environment),
               !requiresExplicitPremiumActivation {
                setPremiumEntitlement(true)
            }
            await transaction.finish()
        }
    }

    private func observeTransactions() async {
        for await update in StoreKit.Transaction.updates {
            guard case .verified(let t) = update else { continue }
            if Self.isPremiumProduct(t.productID),
               Self.acceptsTransactionEnvironment(t.environment) {
                if requiresExplicitPremiumActivation {
                    await t.finish()
                    continue
                }
                await checkEntitlements()
                await t.finish()
            }
        }
    }

    nonisolated private static func isPremiumProduct(_ productID: String) -> Bool {
        productID == AppConfiguration.premiumProductID
            || productID == AppConfiguration.premiumAnnualProductID
    }

    /// TestFlight accepts sandbox transactions only; App Store accepts production only.
    /// Installs with a sandbox receipt (TestFlight / Xcode) always accept sandbox entitlements
    /// even if runtime channel detection falls back to `.appStore`.
    nonisolated private static func acceptsTransactionEnvironment(_ environment: StoreKit.AppStore.Environment) -> Bool {
        switch AppDistribution.channel {
        case .debug:
            return true
        case .testFlight:
            return environment == .sandbox
        case .appStore:
            if AppDistribution.hasSandboxAppStoreReceipt {
                return environment == .sandbox
            }
            return environment == .production
        }
    }

    private func setPremiumEntitlement(_ isPremium: Bool) {
        premiumEntitlement = isPremium
        UserDefaults.standard.set(isPremium, forKey: Self.premiumEntitlementDefaultsKey)
    }

    private func markExplicitPremiumActivationComplete() {
        UserDefaults.standard.set(true, forKey: Self.explicitActivationCompleteKey)
    }

    private static func userFacingMessage(for error: Error, testFlight: Bool) -> String {
        if let purchaseError = error as? PurchaseError {
            return purchaseError.errorDescription ?? error.localizedDescription
        }

        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError:
                return "Couldn't reach the App Store. Check your connection and try again."
            case .notAvailableInStorefront:
                return "Premium isn't available in your App Store region yet."
            case .notEntitled:
                return testFlight
                    ? "No active subscription was found. Sign in with a Sandbox Apple ID under Settings → App Store → Sandbox Account."
                    : "No active subscription was found for this Apple ID."
            case .userCancelled:
                return error.localizedDescription
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == "SKInternalErrorDomain" || nsError.domain == SKErrorDomain {
            if testFlight {
                return "Couldn't complete the purchase. Sign in with a Sandbox Apple ID under Settings → App Store → Sandbox Account, then try again."
            }
            return "Apple couldn't complete the purchase. If this keeps happening, sign out and back into the App Store, or try again later."
        }

        return error.localizedDescription
    }
}

enum PurchaseError: LocalizedError {
    case productUnavailable
    case storeKit(String)

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "Premium is not available yet. Configure the in-app purchase in App Store Connect."
        case .storeKit(let message):
            return message
        }
    }
}
