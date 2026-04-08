import Foundation
import Observation

/// Syncs user preferences to iCloud
@Observable
@MainActor
final class CloudSettingsService {
    private let store = NSUbiquitousKeyValueStore.default
    
    private enum Keys {
        static let currency = "priceDisplayCurrency"
    }
    
    init() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.handleExternalChange()
        }
        store.synchronize()
    }
    
    func saveCurrency(_ currency: PriceDisplayCurrency) {
        store.set(currency.rawValue, forKey: Keys.currency)
        store.synchronize()
    }
    
    func loadCurrency() -> PriceDisplayCurrency? {
        guard let raw = store.string(forKey: Keys.currency) else { return nil }
        return PriceDisplayCurrency(rawValue: raw)
    }
    
    var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
    
    private func handleExternalChange() {
        NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let cloudSettingsDidChange = Notification.Name("cloudSettingsDidChange")
}
