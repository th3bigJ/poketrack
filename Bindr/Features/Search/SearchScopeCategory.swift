import Foundation

/// Horizontal filter chips on the universal search screen.
enum SearchScopeCategory: String, CaseIterable, Identifiable, Hashable {
    case all
    case collection
    case cards
    case sets
    case pokemon
    case sealed
    case decks
    case binders
    case posts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .collection: return "Collection"
        case .cards: return "Cards"
        case .sets: return "Sets"
        case .pokemon: return "Pokémon"
        case .sealed: return "Sealed"
        case .decks: return "Decks"
        case .binders: return "Binders"
        case .posts: return "Posts"
        }
    }

    /// Whether card results should be limited to the user's owned copies.
    var usesCollectionScope: Bool {
        self == .collection
    }

    /// Owned collection cards shown alongside catalogue results on the All tab.
    var showsOwnedCollectionCards: Bool {
        self == .all
    }

    var showsCatalogSets: Bool {
        self == .all || self == .sets
    }

    var showsCatalogPokemon: Bool {
        self == .all || self == .pokemon
    }

    var showsCatalogCards: Bool {
        self == .all || self == .cards || self == .collection
    }

    var showsSealedProducts: Bool {
        self == .all || self == .sealed
    }

    var showsDecks: Bool {
        self == .all || self == .decks
    }

    var showsBinders: Bool {
        self == .all || self == .binders
    }

    var showsPosts: Bool {
        self == .all || self == .posts
    }
}
