import Foundation

enum TradeStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case pending
    case countered
    case accepted
    case complete
    case cancelled

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .countered: return "Countered"
        case .accepted: return "Accepted"
        case .complete: return "Complete"
        case .cancelled: return "Cancelled"
        }
    }
}

enum TradeStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case countered = "Countered"
    case accepted = "Accepted"
    case complete = "Complete"

    var id: String { rawValue }

    var matchingStatus: TradeStatus? {
        switch self {
        case .all: return nil
        case .pending: return .pending
        case .countered: return .countered
        case .accepted: return .accepted
        case .complete: return .complete
        }
    }
}

struct Trade: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let initiatorID: UUID
    let receiverID: UUID
    let status: TradeStatus
    let cashInitiator: Double
    let cashReceiver: Double
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case initiatorID = "initiator_id"
        case receiverID = "receiver_id"
        case status
        case cashInitiator = "cash_initiator"
        case cashReceiver = "cash_receiver"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TradeItem: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let tradeID: UUID
    let ownerID: UUID
    let cardID: String
    let variantKey: String
    let quantity: Int
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case tradeID = "trade_id"
        case ownerID = "owner_id"
        case cardID = "card_id"
        case variantKey = "variant_key"
        case quantity
        case createdAt = "created_at"
    }
}

struct TradeWithItems: Identifiable, Sendable {
    let trade: Trade
    let initiatorItems: [TradeItem]
    let receiverItems: [TradeItem]

    var id: UUID { trade.id }

    func myItems(currentUserID: UUID) -> [TradeItem] {
        trade.initiatorID == currentUserID ? initiatorItems : receiverItems
    }

    func theirItems(currentUserID: UUID) -> [TradeItem] {
        trade.initiatorID == currentUserID ? receiverItems : initiatorItems
    }

    func myCash(currentUserID: UUID) -> Double {
        trade.initiatorID == currentUserID ? trade.cashInitiator : trade.cashReceiver
    }

    func theirCash(currentUserID: UUID) -> Double {
        trade.initiatorID == currentUserID ? trade.cashReceiver : trade.cashInitiator
    }

    func counterpartID(currentUserID: UUID) -> UUID {
        trade.initiatorID == currentUserID ? trade.receiverID : trade.initiatorID
    }
}

struct NewTradeItemInput: Identifiable, Hashable, Sendable {
    let id: UUID
    let cardID: String
    let variantKey: String
    let quantity: Int

    init(cardID: String, variantKey: String = "normal", quantity: Int = 1) {
        self.id = UUID()
        self.cardID = cardID
        self.variantKey = variantKey
        self.quantity = quantity
    }
}

struct TradeSuggestion: Identifiable, Sendable {
    let id: UUID
    let friend: SocialProfile
    let matchType: MatchType
    let matchingCardIDs: [String]

    enum MatchType: Sendable {
        case theyHaveWhatIWant
        case iHaveWhatTheyWant
        case mutual
    }

    init(friend: SocialProfile, matchType: MatchType, matchingCardIDs: [String]) {
        self.id = UUID()
        self.friend = friend
        self.matchType = matchType
        self.matchingCardIDs = matchingCardIDs
    }
}
