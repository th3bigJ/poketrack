import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class StoreKitService {
    private(set) var isPremium = false
    private(set) var products: [Product] = []
    private(set) var purchaseError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
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
        isPremium = premium
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
                isPremium = true
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
                isPremium = true
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
