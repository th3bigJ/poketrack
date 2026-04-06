import Foundation

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
    let isActive: Bool
    let noPricing: Bool
    let imageLowSrc: String
    let imageHighSrc: String?

    enum CodingKeys: String, CodingKey {
        case masterCardId, externalId, tcgdex_id, tcgdexId, localId, setCode, setTcgdexId, cardNumber, cardName
        case fullDisplayName, rarity, category, stage, hp, elementTypes, dexIds, subtypes
        case trainerType, energyType, regulationMark, evolveFrom, artist, isActive, noPricing, imageLowSrc, imageHighSrc
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
        isActive = try c.decode(Bool.self, forKey: .isActive)
        noPricing = try c.decode(Bool.self, forKey: .noPricing)
        imageLowSrc = try c.decode(String.self, forKey: .imageLowSrc)
        imageHighSrc = try c.decodeIfPresent(String.self, forKey: .imageHighSrc)
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
        try c.encode(isActive, forKey: .isActive)
        try c.encode(noPricing, forKey: .noPricing)
        try c.encode(imageLowSrc, forKey: .imageLowSrc)
        try c.encodeIfPresent(imageHighSrc, forKey: .imageHighSrc)
    }
}
