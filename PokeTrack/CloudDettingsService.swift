import Foundation
import Observation

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
    
    /// Check if iCloud is available
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
    
    private func handleExternalChange() {
        // Notify observers that settings changed from another device
        NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let cloudSettingsDidChange = Notification.Name("cloudSettingsDidChange")
}