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

/// Curated palette — richer "jewel-tone" variants are tuned to pair with the procedural
/// textures in ``BinderTexture``. Each colour is the _base_ hue; the texture renderer
/// derives highlights, grain lines, and shadows from this base.
struct BinderColourPalette {
    static let options: [(name: String, color: Color)] = [
        ("obsidian", Color(red: 0.11, green: 0.12, blue: 0.14)),
        ("navy", Color(red: 0.12, green: 0.22, blue: 0.44)),
        ("crimson", Color(red: 0.58, green: 0.12, blue: 0.14)),
        ("amber", Color(red: 0.76, green: 0.52, blue: 0.10)),
        ("emerald", Color(red: 0.09, green: 0.44, blue: 0.28)),
        ("plum", Color(red: 0.36, green: 0.14, blue: 0.46)),
        ("teal", Color(red: 0.08, green: 0.42, blue: 0.46)),
        ("slate", Color(red: 0.30, green: 0.36, blue: 0.44)),
        ("burgundy", Color(red: 0.42, green: 0.10, blue: 0.18)),
        ("cobalt", Color(red: 0.10, green: 0.28, blue: 0.62)),
        ("olive", Color(red: 0.38, green: 0.42, blue: 0.18)),
        ("midnight", Color(red: 0.08, green: 0.10, blue: 0.22)),
        // Legacy colour names — kept so existing binders keep a sensible hue after the
        // palette shift. Map older names to the closest new tone.
        ("red", Color(red: 0.58, green: 0.12, blue: 0.14)),
        ("blue", Color(red: 0.12, green: 0.22, blue: 0.44)),
        ("green", Color(red: 0.09, green: 0.44, blue: 0.28)),
        ("purple", Color(red: 0.36, green: 0.14, blue: 0.46)),
        ("orange", Color(red: 0.76, green: 0.52, blue: 0.10)),
        ("yellow", Color(red: 0.76, green: 0.60, blue: 0.15)),
        ("pink", Color(red: 0.62, green: 0.24, blue: 0.42)),
        ("brown", Color(red: 0.36, green: 0.22, blue: 0.14)),
        ("grey", Color(red: 0.30, green: 0.36, blue: 0.44)),
        ("charcoal", Color(red: 0.18, green: 0.20, blue: 0.22)),
        ("indigo", Color(red: 0.22, green: 0.18, blue: 0.52)),
        ("cyan", Color(red: 0.10, green: 0.42, blue: 0.52)),
        ("mint", Color(red: 0.22, green: 0.52, blue: 0.42)),
        ("magenta", Color(red: 0.58, green: 0.14, blue: 0.42)),
        ("rose", Color(red: 0.62, green: 0.24, blue: 0.32)),
        ("coral", Color(red: 0.68, green: 0.32, blue: 0.26)),
        ("sky", Color(red: 0.18, green: 0.38, blue: 0.58)),
        ("violet", Color(red: 0.38, green: 0.22, blue: 0.60)),
        ("gold", Color(red: 0.76, green: 0.52, blue: 0.10)),
        ("lime", Color(red: 0.38, green: 0.48, blue: 0.18)),
        ("tan", Color(red: 0.46, green: 0.34, blue: 0.22)),
        ("forest", Color(red: 0.09, green: 0.44, blue: 0.28)),
    ]

    /// The subset of the palette surfaced to users in the picker (curated, no
    /// duplicates). Twelve options — fits a 6×2 or 4×3 grid cleanly.
    static let pickerOptions: [(name: String, color: Color)] = Array(options.prefix(12))

    static func color(named name: String) -> Color {
        options.first(where: { $0.name == name })?.color
            ?? pickerOptions[0].color
    }

    /// Human-readable label for a colour name ("navy" → "Navy").
    static func displayName(for colourName: String) -> String {
        let key = colourName.isEmpty ? pickerOptions[0].name : colourName
        return key.prefix(1).uppercased() + key.dropFirst()
    }
}

/// Procedural material applied on top of the binder's base colour. Encodes as
/// its raw value — new bindings default to `.leather`; unknown/legacy values
/// fall back to `.smooth` so pre-texture binders still render.
enum BinderTexture: String, CaseIterable, Identifiable, Codable {
    case leather
    case suede
    case felt
    case linen
    case carbon
    case smooth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leather: return "Leather"
        case .suede:   return "Suede"
        case .felt:    return "Felt"
        case .linen:   return "Linen"
        case .carbon:  return "Carbon"
        case .smooth:  return "Smooth"
        }
    }

    /// SF Symbol shown in the texture picker — approximates each material.
    var pickerSymbol: String {
        switch self {
        case .leather: return "rectangle.grid.1x2"
        case .suede:   return "circle.grid.3x3.fill"
        case .felt:    return "scribble.variable"
        case .linen:   return "square.grid.3x3.square"
        case .carbon:  return "square.grid.4x3.fill"
        case .smooth:  return "rectangle.fill"
        }
    }

    /// Normalised (0…1) overall darkness of the surface pattern — used by the
    /// renderer to pick contrast for grain lines and highlights.
    var grainStrength: Double {
        switch self {
        case .leather: return 0.55
        case .suede:   return 0.40
        case .felt:    return 0.60
        case .linen:   return 0.50
        case .carbon:  return 0.70
        case .smooth:  return 0.20
        }
    }
}

@Model final class Binder {
    /// CloudKit: stored attributes need defaults (or optionals) on the model.
    var id: UUID = UUID()
    var title: String = ""
    var pageLayout: String = BinderPageLayout.fixed(rows: 3, columns: 3).rawValue
    var colour: String = ""
    /// Material applied on top of ``colour``. Stored as the ``BinderTexture`` raw value.
    /// Default is `"smooth"` so binders saved before textures existed still render.
    var texture: String = BinderTexture.smooth.rawValue
    var createdAt: Date = Date()
    /// CloudKit: to-many relationships must be optional.
    @Relationship(deleteRule: .cascade, inverse: \BinderSlot.binder)
    var slots: [BinderSlot]? = []

    init(
        title: String,
        pageLayout: BinderPageLayout,
        colour: String,
        texture: BinderTexture = .leather
    ) {
        self.id = UUID()
        self.title = title
        self.pageLayout = pageLayout.rawValue
        self.colour = colour
        self.texture = texture.rawValue
        self.createdAt = Date()
    }

    var layout: BinderPageLayout {
        BinderPageLayout(rawValue: pageLayout)
    }

    /// Resolves the stored `texture` string to an enum, falling back to `.smooth`
    /// for legacy values (this matches how binders saved before textures existed behave).
    var textureKind: BinderTexture {
        BinderTexture(rawValue: texture) ?? .smooth
    }

    var resolvedColour: Color {
        BinderColourPalette.color(named: colour)
    }

    /// Deterministic seed derived from the binder id — keeps each binder's
    /// procedural texture pattern stable across renders.
    var textureSeed: Int {
        // Stable, bounded hash. `UUID.hashValue` varies per process, so mix the
        // UUID bytes directly for a reproducible seed across app launches.
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return bytes.reduce(5381) { ($0 &* 33) &+ Int($1) }
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
