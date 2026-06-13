import Foundation

enum AppDistributionChannel: Equatable {
    case debug
    case testFlight
    case appStore
}

enum AppDistribution {
    /// Where this build is running — drives StoreKit environment rules.
    static var channel: AppDistributionChannel {
        #if DEBUG
        return .debug
        #else
        return isTestFlightBuild ? .testFlight : .appStore
        #endif
    }

    /// True when the app was installed via TestFlight.
    static var isTestFlight: Bool {
        channel == .testFlight
    }

    /// TestFlight IAP always bills through Apple's sandbox — never production App Store.
    static var requiresSandboxIAP: Bool {
        isTestFlight
    }

    private static var isTestFlightBuild: Bool {
        if isSandboxAppStoreReceipt { return true }
        return embeddedProvisioningProfileContainsTestFlightMarker
    }

    private static var isSandboxAppStoreReceipt: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// TestFlight builds include `beta-reports-active` in the embedded profile.
    private static var embeddedProvisioningProfileContainsTestFlightMarker: Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let profile = String(data: data, encoding: .ascii) else {
            return false
        }
        return profile.contains("beta-reports-active")
    }
}
