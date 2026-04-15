import Foundation

/// First-level destinations from universal search (not `Card` — cards use `NavigationLink(value: Card)`).
enum SearchNavRoot: Hashable {
    case set(TCGSet)
    case dex(dexId: Int, displayName: String)
    case onePieceCharacter(name: String)
    case onePieceSubtype(name: String)
}
