import Foundation

/// First-level destinations from universal search (not `Card` — cards use `NavigationLink(value: Card)`).
enum SearchNavRoot: Hashable {
    case set(TCGSet, brand: TCGBrand)
    case dex(dexId: Int, displayName: String, brand: TCGBrand)
    case onePieceCharacter(name: String, brand: TCGBrand)
    case onePieceSubtype(name: String, brand: TCGBrand)
}
