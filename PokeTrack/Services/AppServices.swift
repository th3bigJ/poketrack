import Foundation
import Observation

@Observable
@MainActor
final class AppServices {
    let cardData = CardDataService()
    let pricing = PricingService()
    let store = StoreKitService()

    func bootstrap() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pricing.refreshFXRate() }
            group.addTask { await self.cardData.loadSets() }
            group.addTask { await self.store.loadProducts() }
        }
        await store.checkEntitlements()
    }
}
