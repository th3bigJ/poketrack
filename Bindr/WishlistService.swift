import Foundation
import SwiftData
import Observation

/// Free-tier cap for wishlist rows (not on the main actor so `WishlistError` can format messages).
enum WishlistFreeTier {
    static let maxItems = 5
}

/// Manages wishlist operations with premium feature gating
@Observable
@MainActor
final class WishlistService {
    private let modelContext: ModelContext
    private let store: StoreKitService
    
    private(set) var items: [WishlistItem] = []
    private(set) var error: String?
    
    init(modelContext: ModelContext, store: StoreKitService) {
        self.modelContext = modelContext
        self.store = store
        loadItems()
    }
    
    /// Load all wishlist items
    func loadItems() {
        do {
            items = try fetchItems()
        } catch {
            self.error = "Failed to load wishlist: \(error.localizedDescription)"
        }
    }

    private func fetchItems() throws -> [WishlistItem] {
        let descriptor = FetchDescriptor<WishlistItem>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    /// Check if user can add more wishlist items
    var canAddItem: Bool {
        let currentItems = (try? fetchItems()) ?? items
        if store.isPremium {
            return true // Unlimited for premium users
        }
        return currentItems.count < WishlistFreeTier.maxItems
    }
    
    /// Add a card to the wishlist
    func addItem(cardID: String, variantKey: String, notes: String = "") throws {
        guard canAddItem else {
            throw WishlistError.limitReached
        }
        
        // Check if same card + variant already in wishlist
        let currentItems = try fetchItems()
        if currentItems.contains(where: { $0.cardID == cardID && $0.variantKey == variantKey }) {
            throw WishlistError.alreadyExists
        }
        
        let item = WishlistItem(cardID: cardID, variantKey: variantKey, notes: notes)
        modelContext.insert(item)
        
        do {
            try modelContext.save()
            loadItems() // Refresh
        } catch {
            throw WishlistError.saveFailed(error)
        }
    }
    
    /// Remove an item from the wishlist
    func removeItem(_ item: WishlistItem) throws {
        modelContext.delete(item)
        
        do {
            try modelContext.save()
            loadItems()
        } catch {
            throw WishlistError.saveFailed(error)
        }
    }

    /// Removes the row for this card + variant if it exists (no-op if not wishlisted).
    func removeCardVariant(cardID: String, variantKey: String) throws {
        guard let item = items.first(where: { $0.cardID == cardID && $0.variantKey == variantKey }) else { return }
        try removeItem(item)
    }

    /// Remove every wishlist row for this card (all print variants).
    func removeAllItems(forCardID cardID: String) throws {
        let toRemove = items.filter { $0.cardID == cardID }
        guard !toRemove.isEmpty else { return }
        for item in toRemove {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
            loadItems()
        } catch {
            throw WishlistError.saveFailed(error)
        }
    }
    
    /// Update an item's notes
    func updateNotes(for item: WishlistItem, notes: String) throws {
        item.notes = notes
        
        do {
            try modelContext.save()
        } catch {
            throw WishlistError.saveFailed(error)
        }
    }
    
    /// Check if a specific card + variant is in the wishlist
    func isInWishlist(cardID: String, variantKey: String) -> Bool {
        let currentItems = (try? fetchItems()) ?? items
        return currentItems.contains(where: { $0.cardID == cardID && $0.variantKey == variantKey })
    }
    
    /// Check if any variant of a card is in the wishlist
    func isInWishlist(cardID: String) -> Bool {
        let currentItems = (try? fetchItems()) ?? items
        return currentItems.contains(where: { $0.cardID == cardID })
    }
}

enum WishlistError: LocalizedError {
    case limitReached
    case alreadyExists
    case saveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .limitReached:
            return "Free users can save up to \(WishlistFreeTier.maxItems) wishlist items. Upgrade to Premium for unlimited wishlists!"
        case .alreadyExists:
            return "This card is already in your wishlist."
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        }
    }
}
