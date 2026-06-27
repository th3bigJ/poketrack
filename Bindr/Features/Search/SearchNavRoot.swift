import Foundation

/// First-level destinations from universal search (not `Card` — cards use `NavigationLink(value: Card)`).
enum SearchNavRoot: Hashable {
    case set(TCGSet, brand: TCGBrand)
    case dex(dexId: Int, displayName: String, brand: TCGBrand)
    case deck(id: UUID)
    case binder(id: UUID)
}
