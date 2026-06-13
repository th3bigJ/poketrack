import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class StoreKitService {
    private static let premiumEntitlementDefaultsKey = "Bindr.store.premiumEntitlement"

    /// Raw entitlement from StoreKit (before DEBUG overrides).
    private var premiumEntitlement = false
    private(set) var isCheckingEntitlements = false

    /// Effective premium flag for the app. In **Debug** builds, use **Force free tier** on Account to test without Premium.
    var isPremium: Bool {
        #if DEBUG
        if debugForceFreeTier { return false }
        #endif
        return premiumEntitlement
    }

    private(set) var products: [Product] = []
    private(set) var annualProduct: Product?
    private(set) var purchaseError: String?
    private(set) var isRestoring = false
    private(set) var restoreMessage: String?

    /// TestFlight builds bill through Apple's sandbox — testers must sign in under Settings → App Store → Sandbox Account.
    var requiresSandboxAccount: Bool {
        AppDistribution.isTestFlight
    }

    var hasPurchaseOptions: Bool {
        !products.isEmpty
    }

    /// Localized plan prices for paywalls — always matches the App Store storefront currency.
    var subscriptionPricing: PremiumSubscriptionPricing {
        PremiumSubscriptionPricing(monthlyProduct: products.first, annualProduct: annualProduct)
    }

    private var updatesTask: Task<Void, Never>?

    #if DEBUG
    static let forceFreeTierDefaultsKey = "Bindr.debug.forceFreeTier"
    /// When `true`, the app behaves as non‑Premium for testing; StoreKit entitlements are unchanged.
    var debugForceFreeTier = false {
        didSet { UserDefaults.standard.set(debugForceFreeTier, forKey: Self.forceFreeTierDefaultsKey) }
    }
    #endif

    init() {
        premiumEntitlement = UserDefaults.standard.bool(forKey: Self.premiumEntitlementDefaultsKey)
        #if DEBUG
        debugForceFreeTier = UserDefaults.standard.bool(forKey: Self.forceFreeTierDefaultsKey)
        #endif
        updatesTask = Task { await observeTransactions() }
        Task {
            await finishUnfinishedTransactions()
            await checkEntitlements()
        }
    }

    func loadProducts() async {
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
        await fetchAndApplyEntitlements()
    }

    /// Always re-reads StoreKit entitlements. Used by restore so a concurrent launch-time
    /// entitlement check cannot cause the refresh to be skipped.
    private func fetchAndApplyEntitlements() async {
        isCheckingEntitlements = true
        defer { isCheckingEntitlements = false }

        // Drain the async sequence on a background executor so StoreKit's
        // network round-trip doesn't hold @MainActor while Apple's servers respond.
        let premium = await Task.detached(priority: .userInitiated) {
            var found = false
            for await result in StoreKit.Transaction.currentEntitlements {
                guard case .verified(let t) = result else { continue }
                if t.productID == AppConfiguration.premiumProductID || t.productID == AppConfiguration.premiumAnnualProductID {
                    found = true
                    break
                }
            }
            return found
        }.value
        setPremiumEntitlement(premium)
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
                if t.productID == AppConfiguration.premiumProductID || t.productID == AppConfiguration.premiumAnnualProductID {
                    setPremiumEntitlement(true)
                    await t.finish()
                }
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
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
        } catch {
            let message = Self.userFacingMessage(for: error, testFlight: requiresSandboxAccount)
            purchaseError = message
            throw PurchaseError.storeKit(message)
        }
        await fetchAndApplyEntitlements()

        if premiumEntitlement {
            restoreMessage = nil
        } else {
            restoreMessage = requiresSandboxAccount
                ? "No active subscription was found. Make sure you're signed into a Sandbox Apple ID under Settings → App Store → Sandbox Account."
                : "No active subscription was found for this Apple ID."
        }
    }

    /// Clears any transactions left open by a crash or network drop so new purchases can proceed.
    private func finishUnfinishedTransactions() async {
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == AppConfiguration.premiumProductID
                || transaction.productID == AppConfiguration.premiumAnnualProductID {
                setPremiumEntitlement(true)
            }
            await transaction.finish()
        }
    }

    private func observeTransactions() async {
        for await update in StoreKit.Transaction.updates {
            guard case .verified(let t) = update else { continue }
            if t.productID == AppConfiguration.premiumProductID || t.productID == AppConfiguration.premiumAnnualProductID {
                await checkEntitlements()
                await t.finish()
            }
        }
    }

    private func setPremiumEntitlement(_ isPremium: Bool) {
        premiumEntitlement = isPremium
        UserDefaults.standard.set(isPremium, forKey: Self.premiumEntitlementDefaultsKey)
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
            #if DEBUG
            print("[StoreKit] \(nsError.domain) code \(nsError.code): \(nsError)")
            #endif
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
