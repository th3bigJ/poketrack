import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class StoreKitService {
    /// Raw entitlement from StoreKit (before DEBUG overrides).
    private var premiumEntitlement = false

    /// Effective premium flag for the app. In **Debug** builds, use **Force free tier** on Account to test without Premium.
    var isPremium: Bool {
        #if DEBUG
        if debugForceFreeTier { return false }
        #endif
        return premiumEntitlement
    }

    private(set) var products: [Product] = []
    private(set) var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    #if DEBUG
    static let forceFreeTierDefaultsKey = "Bindr.debug.forceFreeTier"
    /// When `true`, the app behaves as non‑Premium for testing; StoreKit entitlements are unchanged.
    var debugForceFreeTier = false {
        didSet { UserDefaults.standard.set(debugForceFreeTier, forKey: Self.forceFreeTierDefaultsKey) }
    }
    #endif

    init() {
        #if DEBUG
        debugForceFreeTier = UserDefaults.standard.bool(forKey: Self.forceFreeTierDefaultsKey)
        #endif
        updatesTask = Task { await observeTransactions() }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [AppConfiguration.premiumProductID])
        } catch {
            purchaseError = error.localizedDescription
            products = []
        }
    }

    func checkEntitlements() async {
        var premium = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            if t.productID == AppConfiguration.premiumProductID {
                premium = true
                break
            }
        }
        premiumEntitlement = premium
    }

    func purchase() async throws {
        purchaseError = nil
        guard let product = products.first else {
            await loadProducts()
            throw PurchaseError.productUnavailable
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let t) = verification else { return }
            if t.productID == AppConfiguration.premiumProductID {
                premiumEntitlement = true
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
        try await AppStore.sync()
        await checkEntitlements()
    }

    private func observeTransactions() async {
        for await update in StoreKit.Transaction.updates {
            guard case .verified(let t) = update else { continue }
            if t.productID == AppConfiguration.premiumProductID {
                premiumEntitlement = true
            }
        }
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
