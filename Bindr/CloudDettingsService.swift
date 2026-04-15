import Foundation
import Observation

enum CloudSyncStatus: Equatable {
    case cloudKitConnected
    case cloudKitFallback
    case iCloudAccountUnavailable
}

/// Syncs user preferences to iCloud using NSUbiquitousKeyValueStore
@Observable
@MainActor
final class CloudSettingsService {
    private let store = NSUbiquitousKeyValueStore.default
    
    private enum Keys {
        static let currency = "priceDisplayCurrency"
        static let browseShowCardName = "browseGridShowCardName"
        static let browseShowSetName = "browseGridShowSetName"
        static let browseShowSetID = "browseGridShowSetID"
        static let browseShowPricing = "browseGridShowPricing"
        static let browseColumnCount = "browseGridColumnCount"
    }
    
    init() {
        // Listen for changes from other devices
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.handleExternalChange()
        }
        
        // Start syncing
        store.synchronize()
    }
    
    /// Save currency preference to iCloud
    func saveCurrency(_ currency: PriceDisplayCurrency) {
        store.set(currency.rawValue, forKey: Keys.currency)
        store.synchronize()
    }
    
    /// Load currency preference from iCloud
    func loadCurrency() -> PriceDisplayCurrency? {
        guard let raw = store.string(forKey: Keys.currency) else { return nil }
        return PriceDisplayCurrency(rawValue: raw)
    }

    func saveBrowseGridOptions(_ options: BrowseGridOptions) {
        store.set(options.showCardName, forKey: Keys.browseShowCardName)
        store.set(options.showSetName, forKey: Keys.browseShowSetName)
        store.set(options.showSetID, forKey: Keys.browseShowSetID)
        store.set(options.showPricing, forKey: Keys.browseShowPricing)
        store.set(Int64(options.columnCount), forKey: Keys.browseColumnCount)
        store.synchronize()
    }

    func loadBrowseGridOptions() -> BrowseGridOptions? {
        let hasStoredValue =
            store.object(forKey: Keys.browseShowCardName) != nil
            || store.object(forKey: Keys.browseShowSetName) != nil
            || store.object(forKey: Keys.browseShowSetID) != nil
            || store.object(forKey: Keys.browseShowPricing) != nil
            || store.object(forKey: Keys.browseColumnCount) != nil

        guard hasStoredValue else { return nil }

        let defaults = BrowseGridOptions()
        return BrowseGridOptions(
            showCardName: store.object(forKey: Keys.browseShowCardName) != nil
                ? store.bool(forKey: Keys.browseShowCardName)
                : defaults.showCardName,
            showSetName: store.object(forKey: Keys.browseShowSetName) != nil
                ? store.bool(forKey: Keys.browseShowSetName)
                : defaults.showSetName,
            showSetID: store.object(forKey: Keys.browseShowSetID) != nil
                ? store.bool(forKey: Keys.browseShowSetID)
                : defaults.showSetID,
            showPricing: store.object(forKey: Keys.browseShowPricing) != nil
                ? store.bool(forKey: Keys.browseShowPricing)
                : defaults.showPricing,
            columnCount: store.object(forKey: Keys.browseColumnCount) != nil
                ? Int(store.longLong(forKey: Keys.browseColumnCount))
                : defaults.columnCount
        )
    }

    var syncStatus: CloudSyncStatus {
        if isCloudKitFallbackActive {
            return .cloudKitFallback
        }
        if FileManager.default.ubiquityIdentityToken != nil {
            return .cloudKitConnected
        }
        return .iCloudAccountUnavailable
    }

    /// Check if iCloud-backed sync is currently available
    var isICloudAvailable: Bool {
        syncStatus == .cloudKitConnected
    }

    var isCloudKitFallbackActive: Bool {
        UserDefaults.standard.bool(forKey: BindrApp.cloudKitFallbackDefaultsKey)
    }

    var cloudKitDiagnostic: String? {
        UserDefaults.standard.string(forKey: BindrApp.cloudKitLastErrorDefaultsKey)
    }
    
    /// `NotificationCenter` delivers this on the queue passed to `addObserver` (`.main` above), but the observer
    /// closure is still `@Sendable` / not MainActor-isolated — keep this `nonisolated` and only post notifications.
    nonisolated private func handleExternalChange() {
        NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let cloudSettingsDidChange = Notification.Name("cloudSettingsDidChange")
}
