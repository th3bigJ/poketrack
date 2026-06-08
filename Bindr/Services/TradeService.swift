import Foundation
import Observation

@Observable
@MainActor
final class TradeService {
    enum TradeServiceError: LocalizedError {
        case notSignedIn
        case missingConfiguration
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in first to use trades."
            case .missingConfiguration:
                return "Supabase config is missing from Info.plist."
            case .invalidResponse:
                return "Could not parse trade data from Supabase."
            case .requestFailed(let message):
                return message
            }
        }
    }

    private struct APIErrorPayload: Decodable {
        let message: String?
        let hint: String?
    }

    private struct TradeInsertRequest: Encodable {
        let initiatorID: UUID
        let receiverID: UUID
        let status: String
        let cashInitiator: Double
        let cashReceiver: Double

        enum CodingKeys: String, CodingKey {
            case initiatorID = "initiator_id"
            case receiverID = "receiver_id"
            case status
            case cashInitiator = "cash_initiator"
            case cashReceiver = "cash_receiver"
        }
    }

    private struct TradeItemInsertRequest: Encodable {
        let tradeID: UUID
        let ownerID: UUID
        let cardID: String
        let variantKey: String
        let quantity: Int

        enum CodingKeys: String, CodingKey {
            case tradeID = "trade_id"
            case ownerID = "owner_id"
            case cardID = "card_id"
            case variantKey = "variant_key"
            case quantity
        }
    }

    private struct TradeStatusPatch: Encodable {
        let status: String
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case status
            case updatedAt = "updated_at"
        }
    }

    private struct TradeCompletionPatch: Encodable {
        let status: String?
        let initiatorCompleted: Bool?
        let receiverCompleted: Bool?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case status
            case initiatorCompleted = "initiator_completed"
            case receiverCompleted = "receiver_completed"
            case updatedAt = "updated_at"
        }
    }

    private struct TradeCancelPatch: Encodable {
        let initiatorID: UUID
        let receiverID: UUID
        let status: String
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case initiatorID = "initiator_id"
            case receiverID = "receiver_id"
            case status
            case updatedAt = "updated_at"
        }
    }

    private struct TradeCounterPatch: Encodable {
        let initiatorID: UUID
        let receiverID: UUID
        let status: String
        let cashInitiator: Double
        let cashReceiver: Double
        let initiatorCompleted: Bool
        let receiverCompleted: Bool
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case initiatorID = "initiator_id"
            case receiverID = "receiver_id"
            case status
            case cashInitiator = "cash_initiator"
            case cashReceiver = "cash_receiver"
            case initiatorCompleted = "initiator_completed"
            case receiverCompleted = "receiver_completed"
            case updatedAt = "updated_at"
        }
    }

    private let authService: SocialAuthService
    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }
    private let maxBatchSize = 250
    private(set) var lastMutationAt: Date = .distantPast

    init(authService: SocialAuthService) {
        self.authService = authService
    }

    func fetchMyTrades() async throws -> [TradeWithItems] {
        let uid = try signedInUserID()
        let token = try signedInAccessToken()

        let trades: [Trade] = try await execute(
            path: "/rest/v1/trades?or=(initiator_id.eq.\(uid.uuidString),receiver_id.eq.\(uid.uuidString))&order=updated_at.desc",
            method: "GET",
            accessToken: token
        )
        guard !trades.isEmpty else { return [] }

        // Auto-cancel expired trades (24h timeout)
        let now = Date()
        for trade in trades {
            if (trade.status == .pending || trade.status == .countered),
               let updatedAt = trade.updatedAt,
               now.timeIntervalSince(updatedAt) > 86400 {
                try? await cancelTrade(id: trade.id)
            }
        }

        let tradeIDs = trades.map(\.id.uuidString).joined(separator: ",")
        let items: [TradeItem] = try await execute(
            path: "/rest/v1/trade_items?trade_id=in.(\(tradeIDs))&order=created_at.asc",
            method: "GET",
            accessToken: token
        )

        return assembleTradeWithItems(trades: trades, items: items)
    }

    func fetchTrade(id: UUID) async throws -> TradeWithItems {
        let token = try signedInAccessToken()

        let trades: [Trade] = try await execute(
            path: "/rest/v1/trades?id=eq.\(id.uuidString)",
            method: "GET",
            accessToken: token
        )
        guard let trade = trades.first else {
            throw TradeServiceError.invalidResponse
        }

        // Auto-cancel if expired
        let now = Date()
        if (trade.status == .pending || trade.status == .countered),
           let updatedAt = trade.updatedAt,
           now.timeIntervalSince(updatedAt) > 86400 {
            try? await cancelTrade(id: id)
            return try await fetchTrade(id: id) // Re-fetch to get cancelled status
        }

        let items: [TradeItem] = try await execute(
            path: "/rest/v1/trade_items?trade_id=eq.\(id.uuidString)&order=created_at.asc",
            method: "GET",
            accessToken: token
        )

        return assembleTradeWithItems(trades: [trade], items: items).first ?? TradeWithItems(trade: trade, initiatorItems: [], receiverItems: [])
    }

    func createTrade(
        receiverID: UUID,
        initiatorCards: [NewTradeItemInput],
        receiverCards: [NewTradeItemInput],
        cashInitiator: Double,
        cashReceiver: Double,
        initialStatus: TradeStatus = .pending
    ) async throws -> Trade {
        let uid = try signedInUserID()
        let token = try signedInAccessToken()

        let tradeBody = TradeInsertRequest(
            initiatorID: uid,
            receiverID: receiverID,
            status: initialStatus.rawValue,
            cashInitiator: cashInitiator,
            cashReceiver: cashReceiver
        )
        let created: [Trade] = try await execute(
            path: "/rest/v1/trades",
            method: "POST",
            accessToken: token,
            body: tradeBody,
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard let trade = created.first else {
            throw TradeServiceError.invalidResponse
        }

        let itemsToInsert = Self.consolidatedInputs(initiatorCards).map {
            TradeItemInsertRequest(tradeID: trade.id, ownerID: uid, cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity)
        } + Self.consolidatedInputs(receiverCards).map {
            TradeItemInsertRequest(tradeID: trade.id, ownerID: receiverID, cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity)
        }

        for batch in itemsToInsert.chunked(into: maxBatchSize) {
            _ = try await execute(
                path: "/rest/v1/trade_items",
                method: "POST",
                accessToken: token,
                body: batch,
                extraHeaders: ["Prefer": "return=minimal"]
            ) as EmptyResponse
        }

        markMutation()
        return trade
    }

    func counterTrade(
        tradeID: UUID,
        originalTrade: Trade,
        newInitiatorCards: [NewTradeItemInput],
        newReceiverCards: [NewTradeItemInput],
        cashInitiator: Double,
        cashReceiver: Double
    ) async throws -> Trade {
        let uid = try signedInUserID()
        let token = try signedInAccessToken()
        let otherPartyID = originalTrade.initiatorID == uid ? originalTrade.receiverID : originalTrade.initiatorID

        // Keep the same trade thread and rotate offer ownership so initiator always
        // represents whoever sent the latest offer.
        let patchBody = TradeCounterPatch(
            initiatorID: uid,
            receiverID: otherPartyID,
            status: "countered",
            cashInitiator: cashInitiator,
            cashReceiver: cashReceiver,
            initiatorCompleted: false,
            receiverCompleted: false,
            updatedAt: Date()
        )
        let updated: [Trade] = try await execute(
            path: "/rest/v1/trades?id=eq.\(tradeID.uuidString)",
            method: "PATCH",
            accessToken: token,
            body: patchBody,
            extraHeaders: ["Prefer": "return=representation"]
        )

        // Replace only the current user's own offer lines. The other party's
        // items (what we're requesting) are locked/read-only in the counter UI
        // and must not be touched — re-inserting them would duplicate them when
        // Supabase RLS silently blocks the broad DELETE (which only permits
        // deleting rows where owner_id = auth.uid()).
        _ = try await execute(
            path: "/rest/v1/trade_items?trade_id=eq.\(tradeID.uuidString)&owner_id=eq.\(uid.uuidString)",
            method: "DELETE",
            accessToken: token,
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptyResponse

        // Only insert the counter-maker's own (new) offer lines. The other
        // party's rows remain in the table unchanged.
        let myItemsToInsert = Self.consolidatedInputs(newInitiatorCards).map {
            TradeItemInsertRequest(tradeID: tradeID, ownerID: uid, cardID: $0.cardID, variantKey: $0.variantKey, quantity: $0.quantity)
        }

        for batch in myItemsToInsert.chunked(into: maxBatchSize) {
            _ = try await execute(
                path: "/rest/v1/trade_items",
                method: "POST",
                accessToken: token,
                body: batch,
                extraHeaders: ["Prefer": "return=minimal"]
            ) as EmptyResponse
        }

        markMutation()
        guard let trade = updated.first else {
            throw TradeServiceError.invalidResponse
        }
        return trade
    }

    func acceptTrade(id: UUID) async throws {
        let token = try signedInAccessToken()
        let body = TradeStatusPatch(status: "accepted", updatedAt: Date())
        _ = try await execute(
            path: "/rest/v1/trades?id=eq.\(id.uuidString)",
            method: "PATCH",
            accessToken: token,
            body: body,
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptyResponse
        markMutation()
    }

    func cancelTrade(id: UUID, counterpartID: UUID? = nil) async throws {
        let token = try signedInAccessToken()
        if let counterpartID, let uid = try? signedInUserID() {
            let body = TradeCancelPatch(
                initiatorID: uid,
                receiverID: counterpartID,
                status: "cancelled",
                updatedAt: Date()
            )
            _ = try await execute(
                path: "/rest/v1/trades?id=eq.\(id.uuidString)",
                method: "PATCH",
                accessToken: token,
                body: body,
                extraHeaders: ["Prefer": "return=minimal"]
            ) as EmptyResponse
        } else {
            let body = TradeStatusPatch(status: "cancelled", updatedAt: Date())
            _ = try await execute(
                path: "/rest/v1/trades?id=eq.\(id.uuidString)",
                method: "PATCH",
                accessToken: token,
                body: body,
                extraHeaders: ["Prefer": "return=minimal"]
            ) as EmptyResponse
        }
        markMutation()
    }

    func completeTrade(id: UUID) async throws {
        let uid = try signedInUserID()
        let token = try signedInAccessToken()

        let existing: TradeWithItems = try await fetchTrade(id: id)
        let current = existing.trade
        let isInitiator = current.initiatorID == uid
        let otherSideAlreadyCompleted = isInitiator ? current.receiverCompleted : current.initiatorCompleted

        let body = TradeCompletionPatch(
            status: otherSideAlreadyCompleted ? "complete" : current.status.rawValue,
            initiatorCompleted: isInitiator ? true : nil,
            receiverCompleted: isInitiator ? nil : true,
            updatedAt: Date()
        )
        let updatedTrades: [Trade] = try await execute(
            path: "/rest/v1/trades?id=eq.\(id.uuidString)",
            method: "PATCH",
            accessToken: token,
            body: body,
            extraHeaders: ["Prefer": "return=representation"]
        )

        if let updated = updatedTrades.first,
           updated.status != .complete,
           updated.initiatorCompleted,
           updated.receiverCompleted {
            let completionBody = TradeStatusPatch(status: "complete", updatedAt: Date())
            _ = try await execute(
                path: "/rest/v1/trades?id=eq.\(id.uuidString)",
                method: "PATCH",
                accessToken: token,
                body: completionBody,
                extraHeaders: ["Prefer": "return=minimal"]
            ) as EmptyResponse
        }
        markMutation()
    }

    // MARK: - Helpers

    private func assembleTradeWithItems(trades: [Trade], items: [TradeItem]) -> [TradeWithItems] {
        var grouped: [UUID: [TradeItem]] = [:]
        for item in items {
            grouped[item.tradeID, default: []].append(item)
        }
        return trades.map { trade in
            let allItems = grouped[trade.id] ?? []
            return TradeWithItems(
                trade: trade,
                initiatorItems: allItems.filter { $0.ownerID == trade.initiatorID },
                receiverItems: allItems.filter { $0.ownerID == trade.receiverID }
            )
        }
    }

    private static func consolidatedInputs(_ inputs: [NewTradeItemInput]) -> [NewTradeItemInput] {
        var orderedKeys: [String] = []
        var quantitiesByKey: [String: Int] = [:]
        var cardIDByKey: [String: String] = [:]
        var variantByKey: [String: String] = [:]

        for input in inputs {
            let key = "\(input.cardID)|\(input.variantKey)"
            if quantitiesByKey[key] == nil {
                orderedKeys.append(key)
                cardIDByKey[key] = input.cardID
                variantByKey[key] = input.variantKey
            }
            quantitiesByKey[key, default: 0] += max(input.quantity, 1)
        }

        return orderedKeys.compactMap { key in
            guard let cardID = cardIDByKey[key],
                  let variantKey = variantByKey[key],
                  let quantity = quantitiesByKey[key] else { return nil }
            return NewTradeItemInput(cardID: cardID, variantKey: variantKey, quantity: quantity)
        }
    }

    private func signedInUserID() throws -> UUID {
        switch authService.authState {
        case .signedOut:
            throw TradeServiceError.notSignedIn
        case .signedIn(let userID, _):
            return userID
        }
    }

    private func signedInAccessToken() throws -> String {
        guard let token = authService.accessToken, !token.isEmpty else {
            throw TradeServiceError.notSignedIn
        }
        return token
    }

    private func execute<T: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        try await execute(path: path, method: method, accessToken: accessToken, body: Optional<String>.none, extraHeaders: extraHeaders)
    }

    private func execute<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        accessToken: String,
        body: Body?,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        guard let baseURL, !publishableKey.isEmpty else {
            throw TradeServiceError.missingConfiguration
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw TradeServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        if let body {
            request.httpBody = try JSONEncoder.tradeJSON.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TradeServiceError.invalidResponse
        }
        if isExpiredJWTResponse(statusCode: http.statusCode, data: data) {
            await authService.restoreSession()
            if let refreshedToken = authService.accessToken,
               !refreshedToken.isEmpty,
               refreshedToken != accessToken {
                return try await execute(
                    path: path,
                    method: method,
                    accessToken: refreshedToken,
                    body: body,
                    extraHeaders: extraHeaders
                )
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder.tradeJSON.decode(APIErrorPayload.self, from: data) {
                throw TradeServiceError.requestFailed(payload.message ?? payload.hint ?? "Supabase request failed with status \(http.statusCode).")
            }
            throw TradeServiceError.requestFailed("Supabase request failed with status \(http.statusCode).")
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw TradeServiceError.invalidResponse
        }
        return try JSONDecoder.tradeJSON.decode(T.self, from: data)
    }

    private func isExpiredJWTResponse(statusCode: Int, data: Data) -> Bool {
        guard statusCode == 401 else { return false }
        guard let payload = try? JSONDecoder.tradeJSON.decode(APIErrorPayload.self, from: data) else { return false }
        let message = (payload.message ?? payload.hint ?? "").lowercased()
        return message.contains("jwt") && message.contains("expired")
    }

    private func markMutation() {
        lastMutationAt = Date()
    }
}

private struct EmptyResponse: Decodable {}

private extension JSONDecoder {
    static var tradeJSON: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var tradeJSON: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
