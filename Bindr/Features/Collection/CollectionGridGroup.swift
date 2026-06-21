import Foundation
import SwiftData

/// One tile in the collection grid. Raw singles with multiple finish variants collapse into a single group.
struct CollectionGridGroup: Identifiable {
    let id: String
    let cardID: String
    let items: [CollectionItem]

    var representativeItem: CollectionItem {
        if let normal = items.first(where: { $0.variantKey == "normal" }) {
            return normal
        }
        return items.max(by: { $0.dateAcquired < $1.dateAcquired }) ?? items[0]
    }

    var totalQuantity: Int {
        items.reduce(0) { $0 + max($1.quantity, 0) }
    }

    var variantKeys: [String] {
        Array(Set(items.map(\.variantKey))).sorted()
    }

    func quantity(forVariantKey key: String) -> Int {
        items.filter { $0.variantKey == key }.reduce(0) { $0 + max($1.quantity, 0) }
    }

    func item(forVariantKey key: String) -> CollectionItem? {
        items.first { $0.variantKey == key }
    }

    var preferredVariantKey: String {
        if variantKeys.contains("normal") { return "normal" }
        return variantKeys.first ?? "normal"
    }
}

enum CollectionGridGrouping {
    static func isGradedItem(_ item: CollectionItem) -> Bool {
        item.itemKind == ProductKind.gradedItem.rawValue
            || !(item.gradingCompany?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func groupKey(
        for item: CollectionItem,
        isSealed: Bool
    ) -> String {
        if isSealed {
            return "sealed|\(String(describing: item.persistentModelID))"
        }
        if isGradedItem(item) {
            return [
                "graded",
                item.cardID,
                item.gradingCompany ?? "",
                item.grade ?? "",
                item.certNumber ?? "",
            ].joined(separator: "|")
        }
        return "card|\(item.cardID)"
    }

    static func groupedItems(
        _ items: [CollectionItem],
        isSealed: (CollectionItem) -> Bool
    ) -> [CollectionGridGroup] {
        var order: [String] = []
        var buckets: [String: [CollectionItem]] = [:]
        order.reserveCapacity(items.count)
        buckets.reserveCapacity(items.count)

        for item in items {
            let key = groupKey(for: item, isSealed: isSealed(item))
            if buckets[key] == nil {
                order.append(key)
            }
            buckets[key, default: []].append(item)
        }

        return order.compactMap { key in
            guard let groupItems = buckets[key], let first = groupItems.first else { return nil }
            return CollectionGridGroup(id: key, cardID: first.cardID, items: groupItems)
        }
    }
}
