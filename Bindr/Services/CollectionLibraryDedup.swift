import Foundation
import SwiftData

/// Merges duplicate collection / wishlist rows before backup or after overlapping imports.
enum CollectionLibraryDedup {
    /// Number of duplicate rows removed (not extra card copies).
    @discardableResult
    static func consolidateDuplicateStacks(in modelContext: ModelContext) throws -> Int {
        var removed = 0
        removed += try consolidateCollectionItems(in: modelContext)
        removed += try consolidateWishlistItems(in: modelContext)
        if removed > 0 {
            try modelContext.save()
        }
        return removed
    }

    @discardableResult
    private static func consolidateCollectionItems(in modelContext: ModelContext) throws -> Int {
        let items = try modelContext.fetch(FetchDescriptor<CollectionItem>())
        var groups: [String: [CollectionItem]] = [:]
        groups.reserveCapacity(items.count)

        for item in items {
            groups[stackKey(for: item), default: []].append(item)
        }

        var removed = 0
        for group in groups.values where group.count > 1 {
            let sorted = group.sorted { $0.dateAcquired < $1.dateAcquired }
            guard let keeper = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                keeper.quantity += max(duplicate.quantity, 0)
                if keeper.purchasePrice == nil {
                    keeper.purchasePrice = duplicate.purchasePrice
                }
                if let lots = duplicate.costLots {
                    for lot in lots {
                        lot.collectionItem = keeper
                    }
                }
                modelContext.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    @discardableResult
    private static func consolidateWishlistItems(in modelContext: ModelContext) throws -> Int {
        let items = try modelContext.fetch(FetchDescriptor<WishlistItem>())
        var groups: [String: [WishlistItem]] = [:]
        for item in items {
            groups[wishlistKey(for: item), default: []].append(item)
        }

        var removed = 0
        for group in groups.values where group.count > 1 {
            let sorted = group.sorted { $0.dateAdded < $1.dateAdded }
            guard let keeper = sorted.first else { continue }
            for duplicate in sorted.dropFirst() {
                if keeper.notes.isEmpty, !duplicate.notes.isEmpty {
                    keeper.notes = duplicate.notes
                }
                if keeper.collectionName == nil {
                    keeper.collectionName = duplicate.collectionName
                }
                modelContext.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    private static func stackKey(for item: CollectionItem) -> String {
        [
            item.itemKind,
            item.cardID,
            item.variantKey,
            item.gradingCompany ?? "",
            item.grade ?? "",
            item.certNumber ?? "",
            item.sealedProductId ?? "",
            item.sealedStatus ?? "",
        ].joined(separator: "\u{1F}")
    }

    private static func wishlistKey(for item: WishlistItem) -> String {
        [
            item.cardID,
            item.variantKey,
            item.collectionName ?? "",
        ].joined(separator: "\u{1F}")
    }
}
