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
        await refreshPremiumAccess(fromExplicitUserAction: false)
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
                guard Self.transactionQualifies(t, relaxEnvironment: true) else { return }
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
            if !premiumEntitlement {
                await refreshPremiumAccess(fromExplicitUserAction: true, attemptStoreSync: true)
            }
            if premiumEntitlement { return }
            throw PurchaseError.storeKit(message)
        }

        if !premiumEntitlement {
            await refreshPremiumAccess(fromExplicitUserAction: true, attemptStoreSync: true)
        }
    }

    func restore() async throws {
        purchaseError = nil
        restoreMessage = nil

        isRestoring = true
        defer { isRestoring = false }

        await refreshPremiumAccess(fromExplicitUserAction: true, attemptStoreSync: false)
        if premiumEntitlement {
            restoreMessage = nil
            return
        }

        var syncErrorMessage: String?
        do {
            try await AppStore.sync()
        } catch {
            syncErrorMessage = Self.userFacingMessage(for: error, testFlight: requiresSandboxAccount)
        }

        await refreshPremiumAccess(fromExplicitUserAction: true, attemptStoreSync: false)
        if premiumEntitlement {
            restoreMessage = nil
            return
        }

        if let syncErrorMessage {
            restoreMessage = """
            Couldn't sync with the App Store (\(syncErrorMessage)). \
            If Subscribe shows you're already subscribed, tap Subscribe once — we'll activate Premium from your Apple ID.
            """
        } else {
            restoreMessage = requiresSandboxAccount
                ? "No active subscription was found on this device. Subscribe here, or sign into a Sandbox Apple ID under Settings → App Store → Sandbox Account if you purchased on another tester account."
                : "No active subscription was found for this Apple ID on this device."
        }
    }

    /// Re-reads Premium access from every StoreKit source Apple exposes.
    private func refreshPremiumAccess(
        fromExplicitUserAction: Bool,
        attemptStoreSync: Bool = false
    ) async {
        entitlementFetchGeneration += 1
        let generation = entitlementFetchGeneration
        isCheckingEntitlements = true
        defer {
            if generation == entitlementFetchGeneration {
                isCheckingEntitlements = false
            }
        }

        if attemptStoreSync {
            try? await AppStore.sync()
        }

        let found = await detectActivePremiumSubscription(fromExplicitUserAction: fromExplicitUserAction)
        guard generation == entitlementFetchGeneration else { return }
        applyPremiumState(found: found, fromExplicitUserAction: fromExplicitUserAction)
    }

    private func detectActivePremiumSubscription(fromExplicitUserAction: Bool) async -> Bool {
        let relaxEnvironment = fromExplicitUserAction && AppDistribution.channel != .appStore

        if await scanCurrentEntitlements(relaxEnvironment: relaxEnvironment) {
            return true
        }
        if await scanSubscriptionProductStatus(relaxEnvironment: relaxEnvironment) {
            return true
        }
        if await scanLatestPremiumTransactions(relaxEnvironment: relaxEnvironment) {
            return true
        }
        return false
    }

    private func scanCurrentEntitlements(relaxEnvironment: Bool) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            for await result in StoreKit.Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                if Self.transactionQualifies(transaction, relaxEnvironment: relaxEnvironment) {
                    return true
                }
            }
            return false
        }.value
    }

    private func scanSubscriptionProductStatus(relaxEnvironment: Bool) async -> Bool {
        if products.isEmpty, annualProduct == nil {
            await loadProducts()
        }

        var candidates = products
        if let annualProduct {
            candidates.append(annualProduct)
        }

        for product in candidates {
            guard Self.isPremiumProduct(product.id),
                  let statuses = try? await product.subscription?.status else { continue }

            for status in statuses {
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    if case .verified(let transaction) = status.transaction,
                       Self.transactionQualifies(transaction, relaxEnvironment: relaxEnvironment) {
                        return true
                    }
                default:
                    continue
                }
            }
        }
        return false
    }

    private func scanLatestPremiumTransactions(relaxEnvironment: Bool) async -> Bool {
        let productIDs = [
            AppConfiguration.premiumProductID,
            AppConfiguration.premiumAnnualProductID
        ]

        for productID in productIDs {
            guard let result = await StoreKit.Transaction.latest(for: productID),
                  case .verified(let transaction) = result,
                  Self.transactionQualifies(transaction, relaxEnvironment: relaxEnvironment) else { continue }
            return true
        }
        return false
    }

    private func applyPremiumState(found: Bool, fromExplicitUserAction: Bool) {
        if found {
            if requiresExplicitPremiumActivation && !fromExplicitUserAction {
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

    /// Clears any transactions left open by a crash or network drop so new purchases can proceed.
    private func finishUnfinishedTransactions() async {
        for await result in StoreKit.Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if Self.isPremiumProduct(transaction.productID),
               Self.transactionQualifies(transaction, relaxEnvironment: !requiresExplicitPremiumActivation),
               !requiresExplicitPremiumActivation {
                setPremiumEntitlement(true)
            }
            await transaction.finish()
        }
    }

    private func observeTransactions() async {
        for await update in StoreKit.Transaction.updates {
            guard case .verified(let t) = update else { continue }
            guard Self.isPremiumProduct(t.productID) else { continue }

            if requiresExplicitPremiumActivation {
                await t.finish()
                continue
            }

            if Self.transactionQualifies(t, relaxEnvironment: false) {
                await refreshPremiumAccess(fromExplicitUserAction: false)
            }
            await t.finish()
        }
    }

    nonisolated private static func isPremiumProduct(_ productID: String) -> Bool {
        productID == AppConfiguration.premiumProductID
            || productID == AppConfiguration.premiumAnnualProductID
    }

    nonisolated private static func transactionQualifies(
        _ transaction: StoreKit.Transaction,
        relaxEnvironment: Bool
    ) -> Bool {
        guard isPremiumProduct(transaction.productID) else { return false }
        guard transaction.revocationDate == nil else { return false }
        guard relaxEnvironment || acceptsTransactionEnvironment(transaction.environment) else { return false }
        if let expiration = transaction.expirationDate, expiration < Date() {
            return false
        }
        return true
    }

    /// TestFlight accepts sandbox transactions only; App Store accepts production only.
    nonisolated private static func acceptsTransactionEnvironment(_ environment: StoreKit.AppStore.Environment) -> Bool {
        switch AppDistribution.channel {
        case .debug:
            return true
        case .testFlight:
            return environment == .sandbox
        case .appStore:
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
        if nsError.domain == SKErrorDomain {
            switch SKError.Code(rawValue: nsError.code) {
            case .cloudServiceNetworkConnectionFailed, .cloudServiceRevoked:
                return "Couldn't reach the App Store. Check your connection and try again."
            case .cloudServicePermissionDenied:
                return testFlight
                    ? "App Store access was denied. Sign in with a Sandbox Apple ID under Settings → App Store → Sandbox Account."
                    : "App Store access was denied. Check Settings → Apple Account → Media & Purchases."
            case .paymentCancelled:
                return "Purchase cancelled."
            default:
                break
            }
        }

        if nsError.domain == "SKInternalErrorDomain" || nsError.domain == SKErrorDomain {
            if testFlight {
                return "Unable to complete request. Sign in with a Sandbox Apple ID under Settings → App Store → Sandbox Account, then try again."
            }
            return "Unable to complete request. Sign out and back into the App Store in Settings, then try again."
        }

        if error.localizedDescription.localizedCaseInsensitiveContains("unable to complete") {
            return testFlight
                ? "Unable to complete request. Sign in with a Sandbox Apple ID under Settings → App Store → Sandbox Account, then try again."
                : "Unable to complete request. Sign out and back into the App Store in Settings, then try again."
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
