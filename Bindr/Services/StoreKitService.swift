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
        Task { await checkEntitlements() }
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
        } catch {
            purchaseError = error.localizedDescription
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
    }

    func restore() async throws {
        purchaseError = nil
        restoreMessage = nil
        isRestoring = true
        defer { isRestoring = false }

        try await AppStore.sync()
        await fetchAndApplyEntitlements()

        if premiumEntitlement {
            restoreMessage = nil
        } else {
            restoreMessage = "No active subscription was found for this Apple ID."
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
}

enum PurchaseError: LocalizedError {
    case productUnavailable

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "Premium is not available yet. Configure the in-app purchase in App Store Connect."
        }
    }
}
