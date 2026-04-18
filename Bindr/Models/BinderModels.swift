import SwiftData
import Foundation
import SwiftUI

struct BinderPageLayout: Codable, Hashable {
    private enum Kind: String, Codable {
        case fixed
        case freeScroll
    }

    private let kind: Kind
    private let fixedRows: Int
    private let fixedColumns: Int

    static let freeScroll = BinderPageLayout(kind: .freeScroll, rows: 3, columns: 3)

    static func fixed(rows: Int, columns: Int) -> BinderPageLayout {
        BinderPageLayout(kind: .fixed, rows: rows, columns: columns)
    }

    init(rawValue: String) {
        switch rawValue {
        case "fourSlot":
            self = .fixed(rows: 2, columns: 2)
        case "nineSlot":
            self = .fixed(rows: 3, columns: 3)
        case "twelveSlot":
            self = .fixed(rows: 3, columns: 4)
        case "sixteenSlot":
            self = .fixed(rows: 4, columns: 4)
        case "freeScroll":
            self = .freeScroll
        default:
            if rawValue.hasPrefix("fixed:") {
                let size = rawValue.replacingOccurrences(of: "fixed:", with: "")
                let parts = size.split(separator: "x")
                if parts.count == 2,
                   let rows = Int(parts[0]),
                   let columns = Int(parts[1]) {
                    self = .fixed(rows: rows, columns: columns)
                    return
                }
            }
            self = .fixed(rows: 3, columns: 3)
        }
    }

    private init(kind: Kind, rows: Int, columns: Int) {
        self.kind = kind
        self.fixedRows = max(1, min(rows, 5))
        self.fixedColumns = max(1, min(columns, 5))
    }

    var rawValue: String {
        switch kind {
        case .freeScroll:
            return "freeScroll"
        case .fixed:
            return "fixed:\(rows)x\(columns)"
        }
    }

    var isFreeScroll: Bool { kind == .freeScroll }

    var displayName: String {
        isFreeScroll ? "Free Scroll" : "\(rows)×\(columns)"
    }

    var slotsPerPage: Int? {
        isFreeScroll ? nil : rows * columns
    }

    var columns: Int {
        isFreeScroll ? 3 : fixedColumns
    }

    var rows: Int {
        isFreeScroll ? 3 : fixedRows
    }
}

struct BinderColourPalette {
    static let options: [(name: String, color: Color)] = [
        ("red", .red),
        ("coral", Color(red: 0.97, green: 0.45, blue: 0.39)),
        ("orange", .orange),
        ("amber", Color(red: 0.96, green: 0.64, blue: 0.15)),
        ("yellow", .yellow),
        ("gold", Color(red: 0.86, green: 0.70, blue: 0.18)),
        ("lime", Color(red: 0.62, green: 0.83, blue: 0.24)),
        ("green", .green),
        ("forest", Color(red: 0.18, green: 0.48, blue: 0.24)),
        ("mint", .mint),
        ("teal", .teal),
        ("cyan", .cyan),
        ("blue", .blue),
        ("sky", Color(red: 0.37, green: 0.70, blue: 0.96)),
        ("indigo", .indigo),
        ("purple", .purple),
        ("violet", Color(red: 0.54, green: 0.35, blue: 0.96)),
        ("pink", .pink),
        ("rose", Color(red: 0.89, green: 0.36, blue: 0.52)),
        ("magenta", Color(red: 0.78, green: 0.20, blue: 0.57)),
        ("brown", .brown),
        ("tan", Color(red: 0.73, green: 0.60, blue: 0.44)),
        ("slate", Color(red: 0.39, green: 0.46, blue: 0.55)),
        ("charcoal", Color(red: 0.24, green: 0.27, blue: 0.31)),
        ("grey", Color(uiColor: .systemGray2))
    ]

    static func color(named name: String) -> Color {
        options.first(where: { $0.name == name })?.color ?? Color(uiColor: .systemGray2)
    }
}

@Model final class Binder {
    /// CloudKit: stored attributes need defaults (or optionals) on the model.
    var id: UUID = UUID()
    var title: String = ""
    var pageLayout: String = BinderPageLayout.fixed(rows: 3, columns: 3).rawValue
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
        BinderPageLayout(rawValue: pageLayout)
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
