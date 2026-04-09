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
        UserDefaults.standard.bool(forKey: PokeTrackApp.cloudKitFallbackDefaultsKey)
    }

    var cloudKitDiagnostic: String? {
        UserDefaults.standard.string(forKey: PokeTrackApp.cloudKitLastErrorDefaultsKey)
    }
    
    private func handleExternalChange() {
        // Notify observers that settings changed from another device
        NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let cloudSettingsDidChange = Notification.Name("cloudSettingsDidChange")
}
