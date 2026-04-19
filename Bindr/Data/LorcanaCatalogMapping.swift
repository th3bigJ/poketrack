import Foundation

// MARK: - R2 JSON (`lorcana/…`)

struct LorcanaSetRow: Codable, Sendable {
    let id: String
    let setCode: String
    let name: String
    let scannerEnExpansionNumber: String?
    let releaseDate: String?
    let cardCount: Int?
    let imagePath: String?

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
            seriesName: nil,
            logoSrc: imagePath ?? "",
            symbolSrc: nil,
            scannerEnExpansionNumber: scannerEnExpansionNumber
        )
    }
}

struct LorcanaCardDTO: Decodable, Sendable {
    let priceKey: String
    let cardNumber: String
    let printedNumber: String?
    let name: String
    let setCode: String
    let variant: String?
    let rarity: String?
    let supertype: String?
    let subtypes: [String]?
    let cost: Int?
    let strength: Int?
    let willpower: Int?
    let lore_value: Int?
    let flavor_text: String?
    let effect: String?
    let scrydexSlug: String?
    let imagePath: String?
    let tcgplayerProductId: Int?
    /// Decoded from `ink_type` in JSON; exposed for ``LorcanaCatalogMapping``.
    fileprivate(set) var inkTypeRaw: String?

    enum CodingKeys: String, CodingKey {
        case priceKey, cardNumber, printedNumber, name, setCode, variant, rarity, supertype, subtypes
        case cost, strength, willpower, lore_value, flavor_text, effect, scrydexSlug, imagePath, tcgplayerProductId
        case ink_type
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardNumber = try c.decode(String.self, forKey: .cardNumber)
        printedNumber = try c.decodeIfPresent(String.self, forKey: .printedNumber)
        name = try c.decode(String.self, forKey: .name)
        setCode = try c.decode(String.self, forKey: .setCode)
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        rarity = try c.decodeIfPresent(String.self, forKey: .rarity)
        supertype = try c.decodeIfPresent(String.self, forKey: .supertype)
        subtypes = try c.decodeIfPresent([String].self, forKey: .subtypes)
        cost = try c.decodeIfPresent(Int.self, forKey: .cost)
        strength = try c.decodeIfPresent(Int.self, forKey: .strength)
        willpower = try c.decodeIfPresent(Int.self, forKey: .willpower)
        lore_value = try c.decodeIfPresent(Int.self, forKey: .lore_value)
        flavor_text = try c.decodeIfPresent(String.self, forKey: .flavor_text)
        effect = try c.decodeIfPresent(String.self, forKey: .effect)
        scrydexSlug = try c.decodeIfPresent(String.self, forKey: .scrydexSlug)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        inkTypeRaw = try c.decodeIfPresent(String.self, forKey: .ink_type)
        if let intValue = try c.decodeIfPresent(Int.self, forKey: .tcgplayerProductId) {
            tcgplayerProductId = intValue
        } else if let stringValue = try c.decodeIfPresent(String.self, forKey: .tcgplayerProductId) {
            tcgplayerProductId = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            tcgplayerProductId = nil
        }
        if let explicit = try c.decodeIfPresent(String.self, forKey: .priceKey), !explicit.isEmpty {
            priceKey = explicit
        } else {
            priceKey = "\(setCode)::\(cardNumber)::\(variant ?? "normal")"
        }
    }
}

enum LorcanaCatalogMapping {
    static func card(from dto: LorcanaCardDTO) -> Card {
        let pricingVariants: [String]? = dto.variant.map { [$0] }
        let ink = dto.inkTypeRaw.map { [$0] }

        return Card(
            masterCardId: TCGBrand.lorcanaMasterIdPrefix + dto.priceKey,
            externalId: dto.scrydexSlug,
            tcgdex_id: nil,
            localId: localIdFromCardNumber(dto.cardNumber),
            setCode: dto.setCode,
            setTcgdexId: nil,
            cardNumber: dto.cardNumber,
            cardName: dto.name,
            fullDisplayName: nil,
            rarity: dto.rarity,
            category: dto.supertype,
            stage: nil,
            hp: dto.willpower ?? dto.strength,
            elementTypes: ink,
            dexIds: nil,
            subtypes: dto.subtypes,
            trainerType: nil,
            energyType: dto.inkTypeRaw,
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
            flavorText: dto.flavor_text,
            pricingVariants: pricingVariants,
            tcgplayerProductId: dto.tcgplayerProductId.map { String($0) },
            printedNumber: dto.printedNumber,
            lcVariant: dto.variant,
            lcCost: dto.cost,
            lcStrength: dto.strength,
            lcWillpower: dto.willpower,
            lcLore: dto.lore_value
        )
    }

    private static func localIdFromCardNumber(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = t.lastIndex(of: "-") {
            let tail = String(t[t.index(after: idx)...])
            return tail.isEmpty ? nil : tail
        }
        return t.isEmpty ? nil : t
    }
}
