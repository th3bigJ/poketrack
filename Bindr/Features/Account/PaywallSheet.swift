import StoreKit
import SwiftUI

/// Compatibility wrapper around `PremiumUpgradeView`.
///
/// `PaywallSheet` is presented from 14+ call sites — keeping the
/// public surface identical means none of them need to change when we
/// redesign the underlying experience. All visual work lives in
/// `PremiumUpgradeView`; this view exists purely as a stable entry point.
struct PaywallSheet: View {
    var body: some View {
        PremiumUpgradeView()
    }
}
