import SwiftData
import Foundation

enum BinderPageLayout: String, Codable, CaseIterable {
    case nineSlot   = "nineSlot"
    case twelveSlot = "twelveSlot"
    case freeScroll = "freeScroll"

    var displayName: String {
        switch self {
        case .nineSlot:   return "3×3 Pages"
        case .twelveSlot: return "4×3 Pages"
        case .freeScroll: return "Free Scroll"
        }
    }

    var slotsPerPage: Int? {
        switch self {
        case .nineSlot:   return 9
        case .twelveSlot: return 12
        case .freeScroll: return nil
        }
    }

    var columns: Int {
        switch self {
        case .nineSlot:   return 3
        case .twelveSlot: return 4
        case .freeScroll: return 3
        }
    }
}

@Model final class Binder {
    /// CloudKit: stored attributes need defaults (or optionals) on the model.
    var id: UUID = UUID()
    var title: String = ""
    var pageLayout: String = BinderPageLayout.nineSlot.rawValue
    var colour: String = ""
    var createdAt: Date = Date()
    /// CloudKit: to-many relationships must be optional.
    @Relationship(deleteRule: .cascade, inverse: \BinderSlot.binder)
    var slots: [BinderSlot]? = []

    init(title: String, pageLayout: BinderPageLayout, colour: String) {
        self.id = UUID()
        self.title = title
        self.pageLayout = pageLayout.rawValue
        self.colour = colour
        self.createdAt = Date()
    }

    var layout: BinderPageLayout {
        BinderPageLayout(rawValue: pageLayout) ?? .nineSlot
    }
}

@Model final class BinderSlot {
    var position: Int = 0
    var cardID: String = ""
    var variantKey: String = "normal"
    var cardName: String = ""
    var binder: Binder?

    init(position: Int, cardID: String, variantKey: String, cardName: String) {
        self.position = position
        self.cardID = cardID
        self.variantKey = variantKey
        self.cardName = cardName
    }
}

extension Binder {
    /// Use this instead of `slots` at call sites — CloudKit stores the relationship as optional.
    var slotList: [BinderSlot] { slots ?? [] }
}
