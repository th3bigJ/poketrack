import Foundation

// MARK: - R2 JSON (onepiece/…)

struct OnePieceSetRow: Codable, Sendable {
    let id: String
    let setCode: String
    let name: String
    let releaseDate: String?
    let cardCount: Int?
    let imagePath: String?
    let setType: String?

    func asTCGSet() -> TCGSet {
        TCGSet(
            internalId: id,
            name: name,
            setKey: setCode,
            code: setCode,
            tcgdexId: nil,
            releaseDate: releaseDate,
            cardCountTotal: cardCount,
            cardCountOfficial: nil,
            seriesName: setType,
            logoSrc: imagePath ?? "",
            symbolSrc: nil
        )
    }
}

struct OnePieceCardDTO: Codable, Sendable {
    let priceKey: String  // derived if absent in JSON: "\(setCode)::\(cardNumber)::\(variant)"
    let cardNumber: String
    let name: String
    let setCode: String
    /// When set, market/history/trends JSON rows are keyed by this TCGplayer product id (not `priceKey`).
    let tcgplayerProductId: Int?
    let variant: String?
    let rarity: String?
    let cardType: [String]?
    let color: [String]?
    let power: Int?
    let life: Int?
    let subtypes: [String]?
    let effect: String?
    let scrydexSlug: String?
    let imagePath: String?

    enum CodingKeys: String, CodingKey {
        case priceKey, cardNumber, name, setCode, tcgplayerProductId
        case variant, rarity, cardType, color, power, life
        case subtypes, effect, scrydexSlug, imagePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardNumber = try c.decode(String.self, forKey: .cardNumber)
        name = try c.decode(String.self, forKey: .name)
        setCode = try c.decode(String.self, forKey: .setCode)
        if let intValue = try c.decodeIfPresent(Int.self, forKey: .tcgplayerProductId) {
            tcgplayerProductId = intValue
        } else if let stringValue = try c.decodeIfPresent(String.self, forKey: .tcgplayerProductId) {
            tcgplayerProductId = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            tcgplayerProductId = nil
        }
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        // `priceKey` was added retroactively; fall back to the canonical derived form used by older sets.
        if let explicit = try c.decodeIfPresent(String.self, forKey: .priceKey), !explicit.isEmpty {
            priceKey = explicit
        } else {
            priceKey = "\(setCode)::\(cardNumber)::\(variant ?? "normal")"
        }
        rarity = try c.decodeIfPresent(String.self, forKey: .rarity)
        cardType = try c.decodeIfPresent([String].self, forKey: .cardType)
        color = try c.decodeIfPresent([String].self, forKey: .color)
        power = try c.decodeIfPresent(Int.self, forKey: .power)
        life = try c.decodeIfPresent(Int.self, forKey: .life)
        subtypes = try c.decodeIfPresent([String].self, forKey: .subtypes)
        effect = try c.decodeIfPresent(String.self, forKey: .effect)
        scrydexSlug = try c.decodeIfPresent(String.self, forKey: .scrydexSlug)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
    }
}

enum OnePieceCatalogMapping {
    static func card(from dto: OnePieceCardDTO) -> Card {
        // One row per variant in catalog: `variant` is the product line for this card (not R2’s placeholder `default`).
        let pricingVariants: [String]? = dto.variant.map { [$0] }

        return Card(
            masterCardId: dto.priceKey,
            externalId: dto.scrydexSlug,
            tcgdex_id: nil,
            localId: localIdFromCardNumber(dto.cardNumber),
            setCode: dto.setCode,
            setTcgdexId: nil,
            cardNumber: dto.cardNumber,
            cardName: dto.name,
            fullDisplayName: nil,
            rarity: dto.rarity,
            category: dto.cardType?.joined(separator: ", "),
            stage: nil,
            hp: dto.power,
            elementTypes: dto.color,
            dexIds: nil,
            subtypes: dto.subtypes,
            trainerType: nil,
            energyType: nil,
            regulationMark: nil,
            evolveFrom: nil,
            artist: nil,
            imageLowSrc: dto.imagePath ?? "",
            imageHighSrc: nil,
            attacks: nil,
            rules: dto.effect,
            subtype: dto.subtypes?.joined(separator: ", "),
            weakness: nil,
            resistance: nil,
            retreatCost: nil,
            flavorText: nil,
            pricingVariants: pricingVariants,
            tcgplayerProductId: dto.tcgplayerProductId.map { String($0) }
        )
    }

    /// Prefer numeric suffix from strings like `OP01-001`.
    private static func localIdFromCardNumber(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = t.lastIndex(of: "-") {
            let tail = String(t[t.index(after: idx)...])
            return tail.isEmpty ? nil : tail
        }
        return t.isEmpty ? nil : t
    }
}

/// On-disk ONE PIECE card JSON (`Bootstrap` prefetch + runtime cache). Pokémon uses `Documents/cards/` separately.
enum OnePieceCatalogDiskCache {
    static let setsManifestHashUserDefaultsKey = "onepiece_catalog_sets_sha256"

    /// Cached copy of `sets/data/sets.json` so bootstrap can fill the browse list without a second download.
    static func setsManifestURL(fileManager: FileManager = .default) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("onepiece", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sets_manifest.json")
    }

    static func writeSetsManifest(data: Data, fileManager: FileManager = .default) throws {
        let url = setsManifestURL(fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func cardsDirectory(fileManager: FileManager = .default) -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("onepiece/cards", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cardsFileURL(setCode: String, fileManager: FileManager = .default) -> URL {
        cardsDirectory(fileManager: fileManager).appendingPathComponent("\(setCode).json")
    }

    static func writeCards(data: Data, setCode: String, fileManager: FileManager = .default) throws {
        let url = cardsFileURL(setCode: setCode, fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
