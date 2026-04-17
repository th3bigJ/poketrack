import SwiftData
import Foundation

enum BinderPageLayout: String, Codable, CaseIterable {
    case fourSlot   = "fourSlot"
    case nineSlot   = "nineSlot"
    case sixteenSlot = "sixteenSlot"
    case twelveSlot = "twelveSlot"
    case freeScroll = "freeScroll"

    static var allCases: [BinderPageLayout] {
        [.fourSlot, .nineSlot, .twelveSlot, .sixteenSlot, .freeScroll]
    }

    var displayName: String {
        switch self {
        case .fourSlot: return "2×2"
        case .nineSlot: return "3×3"
        case .sixteenSlot: return "4×4"
        case .twelveSlot: return "4×3"
        case .freeScroll: return "Free Scroll"
        }
    }

    var slotsPerPage: Int? {
        switch self {
        case .fourSlot: return 4
        case .nineSlot: return 9
        case .sixteenSlot: return 16
        case .twelveSlot: return 12
        case .freeScroll: return nil
        }
    }

    var columns: Int {
        switch self {
        case .fourSlot: return 2
        case .nineSlot: return 3
        case .sixteenSlot, .twelveSlot: return 4
        case .freeScroll: return 3
        }
    }

    var rows: Int {
        switch self {
        case .fourSlot: return 2
        case .nineSlot, .freeScroll: return 3
        case .sixteenSlot: return 4
        case .twelveSlot: return 3
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
