import Foundation

/// One attack line from the card; used for catalog search and scanner matching.
struct CardAttack: Codable, Hashable, Sendable {
    let name: String
    /// Damage as printed, e.g. `"80"`, `"120+"`, or null when none.
    let damage: String?
    /// Energy cost symbols, e.g. `["Fire", "Colorless"]`.
    let cost: [String]?
    /// Effect text describing what the attack does.
    let effect: String?
}

struct Card: Codable, Identifiable, Hashable, Sendable {
    var id: String { masterCardId }

    let masterCardId: String
    let externalId: String?
    let tcgdex_id: String?
    let localId: String?
    let setCode: String
    let setTcgdexId: String?
    let cardNumber: String
    let cardName: String
    let fullDisplayName: String?
    let rarity: String?
    let category: String?
    let stage: String?
    let hp: Int?
    let elementTypes: [String]?
    let dexIds: [Int]?
    let subtypes: [String]?
    let trainerType: String?
    let energyType: String?
    let regulationMark: String?
    let evolveFrom: String?
    let artist: String?
    let imageLowSrc: String
    let imageHighSrc: String?
    /// Pokémon attacks in visual order; OCR from the center of the card can match these.
    let attacks: [CardAttack]?
    /// Trainer / Special Energy rules text from the center of the card.
    let rules: String?
    /// Subtype as a comma-separated string, e.g. "Stage 2, MEGA, ex".
    let subtype: String?
    let weakness: String?
    let resistance: String?
    let retreatCost: Int?
    let flavorText: String?
    /// Available pricing variant keys for this card, e.g. ["holofoil", "reverseHolofoil"].
    let pricingVariants: [String]?
    /// ONE PIECE: TCGplayer product id when market/history JSON rows are keyed by id (not `priceKey`).
    let tcgplayerProductId: String?

    enum CodingKeys: String, CodingKey {
        case masterCardId, externalId, tcgdex_id, tcgdexId, localId, setCode, setTcgdexId, cardNumber, cardName
        case fullDisplayName, rarity, category, stage, hp, elementTypes, dexIds, subtypes
        case trainerType, energyType, regulationMark, evolveFrom, artist, imageLowSrc, imageHighSrc
        case attacks, rules, subtype, weakness, resistance, retreatCost, flavorText, pricingVariants
        case tcgplayerProductId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        masterCardId = try c.decode(String.self, forKey: .masterCardId)
        externalId = try c.decodeIfPresent(String.self, forKey: .externalId)
        tcgdex_id = try c.decodeIfPresent(String.self, forKey: .tcgdex_id)
            ?? c.decodeIfPresent(String.self, forKey: .tcgdexId)
        localId = try c.decodeIfPresent(String.self, forKey: .localId)
        setCode = try c.decode(String.self, forKey: .setCode)
        setTcgdexId = try c.decodeIfPresent(String.self, forKey: .setTcgdexId)
        cardNumber = try c.decode(String.self, forKey: .cardNumber)
        cardName = try c.decode(String.self, forKey: .cardName)
        fullDisplayName = try c.decodeIfPresent(String.self, forKey: .fullDisplayName)
        rarity = try c.decodeIfPresent(String.self, forKey: .rarity)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        stage = try c.decodeIfPresent(String.self, forKey: .stage)
        hp = try c.decodeIfPresent(Int.self, forKey: .hp)
        elementTypes = try c.decodeIfPresent([String].self, forKey: .elementTypes)
        dexIds = try c.decodeIfPresent([Int].self, forKey: .dexIds)
        subtypes = try c.decodeIfPresent([String].self, forKey: .subtypes)
        trainerType = try c.decodeIfPresent(String.self, forKey: .trainerType)
        energyType = try c.decodeIfPresent(String.self, forKey: .energyType)
        regulationMark = try c.decodeIfPresent(String.self, forKey: .regulationMark)
        evolveFrom = try c.decodeIfPresent(String.self, forKey: .evolveFrom)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        imageLowSrc = try c.decode(String.self, forKey: .imageLowSrc)
        imageHighSrc = try c.decodeIfPresent(String.self, forKey: .imageHighSrc)
        attacks = try c.decodeIfPresent([CardAttack].self, forKey: .attacks)
        rules = try c.decodeIfPresent(String.self, forKey: .rules)
        subtype = try c.decodeIfPresent(String.self, forKey: .subtype)
        weakness = try c.decodeIfPresent(String.self, forKey: .weakness)
        resistance = try c.decodeIfPresent(String.self, forKey: .resistance)
        retreatCost = try c.decodeIfPresent(Int.self, forKey: .retreatCost)
        flavorText = try c.decodeIfPresent(String.self, forKey: .flavorText)
        pricingVariants = try c.decodeIfPresent([String].self, forKey: .pricingVariants)
        if let s = try c.decodeIfPresent(String.self, forKey: .tcgplayerProductId) {
            tcgplayerProductId = s
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .tcgplayerProductId) {
            tcgplayerProductId = String(i)
        } else {
            tcgplayerProductId = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(masterCardId, forKey: .masterCardId)
        try c.encodeIfPresent(externalId, forKey: .externalId)
        try c.encodeIfPresent(tcgdex_id, forKey: .tcgdex_id)
        try c.encodeIfPresent(localId, forKey: .localId)
        try c.encode(setCode, forKey: .setCode)
        try c.encodeIfPresent(setTcgdexId, forKey: .setTcgdexId)
        try c.encode(cardNumber, forKey: .cardNumber)
        try c.encode(cardName, forKey: .cardName)
        try c.encodeIfPresent(fullDisplayName, forKey: .fullDisplayName)
        try c.encodeIfPresent(rarity, forKey: .rarity)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(stage, forKey: .stage)
        try c.encodeIfPresent(hp, forKey: .hp)
        try c.encodeIfPresent(elementTypes, forKey: .elementTypes)
        try c.encodeIfPresent(dexIds, forKey: .dexIds)
        try c.encodeIfPresent(subtypes, forKey: .subtypes)
        try c.encodeIfPresent(trainerType, forKey: .trainerType)
        try c.encodeIfPresent(energyType, forKey: .energyType)
        try c.encodeIfPresent(regulationMark, forKey: .regulationMark)
        try c.encodeIfPresent(evolveFrom, forKey: .evolveFrom)
        try c.encodeIfPresent(artist, forKey: .artist)
        try c.encode(imageLowSrc, forKey: .imageLowSrc)
        try c.encodeIfPresent(imageHighSrc, forKey: .imageHighSrc)
        try c.encodeIfPresent(attacks, forKey: .attacks)
        try c.encodeIfPresent(rules, forKey: .rules)
        try c.encodeIfPresent(subtype, forKey: .subtype)
        try c.encodeIfPresent(weakness, forKey: .weakness)
        try c.encodeIfPresent(resistance, forKey: .resistance)
        try c.encodeIfPresent(retreatCost, forKey: .retreatCost)
        try c.encodeIfPresent(flavorText, forKey: .flavorText)
        try c.encodeIfPresent(pricingVariants, forKey: .pricingVariants)
        try c.encodeIfPresent(tcgplayerProductId, forKey: .tcgplayerProductId)
    }

    /// Memberwise initializer for catalog adapters (e.g. One Piece JSON → shared ``Card`` model).
    init(
        masterCardId: String,
        externalId: String?,
        tcgdex_id: String?,
        localId: String?,
        setCode: String,
        setTcgdexId: String?,
        cardNumber: String,
        cardName: String,
        fullDisplayName: String?,
        rarity: String?,
        category: String?,
        stage: String?,
        hp: Int?,
        elementTypes: [String]?,
        dexIds: [Int]?,
        subtypes: [String]?,
        trainerType: String?,
        energyType: String?,
        regulationMark: String?,
        evolveFrom: String?,
        artist: String?,
        imageLowSrc: String,
        imageHighSrc: String?,
        attacks: [CardAttack]?,
        rules: String?,
        subtype: String?,
        weakness: String?,
        resistance: String?,
        retreatCost: Int?,
        flavorText: String?,
        pricingVariants: [String]?,
        tcgplayerProductId: String? = nil
    ) {
        self.masterCardId = masterCardId
        self.externalId = externalId
        self.tcgdex_id = tcgdex_id
        self.localId = localId
        self.setCode = setCode
        self.setTcgdexId = setTcgdexId
        self.cardNumber = cardNumber
        self.cardName = cardName
        self.fullDisplayName = fullDisplayName
        self.rarity = rarity
        self.category = category
        self.stage = stage
        self.hp = hp
        self.elementTypes = elementTypes
        self.dexIds = dexIds
        self.subtypes = subtypes
        self.trainerType = trainerType
        self.energyType = energyType
        self.regulationMark = regulationMark
        self.evolveFrom = evolveFrom
        self.artist = artist
        self.imageLowSrc = imageLowSrc
        self.imageHighSrc = imageHighSrc
        self.attacks = attacks
        self.rules = rules
        self.subtype = subtype
        self.weakness = weakness
        self.resistance = resistance
        self.retreatCost = retreatCost
        self.flavorText = flavorText
        self.pricingVariants = pricingVariants
        self.tcgplayerProductId = tcgplayerProductId
    }

    /// Text included in inverted-index search: name/number/set, **HP**, **attacks** (Pokémon), **rules** (Trainers — often long).
    var searchIndexBlob: String {
        var parts: [String] = [
            cardName,
            cardNumber,
            fullDisplayName ?? "",
            setCode,
        ]
        if let hp {
            parts.append(String(hp))
        }
        if let rules {
            parts.append(rules)
        }
        if let attacks {
            for a in attacks {
                parts.append(a.name)
                if let d = a.damage {
                    parts.append(d)
                }
            }
        }
        if let artist {
            parts.append(artist)
        }
        return parts.joined(separator: " ")
    }
}
