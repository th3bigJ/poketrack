import Foundation

struct Card: Codable, Identifiable, Hashable {
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
}
