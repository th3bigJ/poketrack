import Foundation

enum AppDistribution {
    /// True when the app was installed via TestFlight (sandbox receipt).
    /// App Store production builds use a non-sandbox receipt instead.
    static var isTestFlight: Bool {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }
}
