import Foundation
import Observation

struct SessionCardItem: Codable, Hashable, Sendable {
    let cardID: String
    let variantKey: String
    let quantity: Int

    init(cardID: String, variantKey: String = "normal", quantity: Int = 1) {
        self.cardID = cardID
        self.variantKey = variantKey
        self.quantity = quantity
    }
}

struct SessionOfferData: Codable, Sendable {
    var offering: [SessionCardItem] = []
    var wanting: [SessionCardItem] = []
    var cash: Double = 0
}

struct TradeSession: Codable, Identifiable, Sendable {
    let id: UUID
    let initiatorID: UUID
    let participantID: UUID
    var status: String
    var initiatorData: SessionOfferData
    var participantData: SessionOfferData
    var initiatorOfferSubmitted: Bool
    var participantOfferSubmitted: Bool
    var initiatorAccepted: Bool
    var participantAccepted: Bool
    var executionLock: UUID?
    var tradeRecordID: UUID?
    let createdAt: Date?
    let updatedAt: Date?

    var isFullySubmitted: Bool { initiatorOfferSubmitted && participantOfferSubmitted }
    var isFullyAccepted: Bool { initiatorAccepted && participantAccepted }
    var isCompleted: Bool { status == "completed" || status == "cancelled" }

    func myRole(userID: UUID) -> SessionRole {
        userID == initiatorID ? .initiator : .participant
    }

    func myOfferData(userID: UUID) -> SessionOfferData {
        myRole(userID: userID) == .initiator ? initiatorData : participantData
    }

    func theirOfferData(userID: UUID) -> SessionOfferData {
        myRole(userID: userID) == .initiator ? participantData : initiatorData
    }

    func myOfferSubmitted(userID: UUID) -> Bool {
        myRole(userID: userID) == .initiator ? initiatorOfferSubmitted : participantOfferSubmitted
    }

    func theirOfferSubmitted(userID: UUID) -> Bool {
        myRole(userID: userID) == .initiator ? participantOfferSubmitted : initiatorOfferSubmitted
    }

    func myAccepted(userID: UUID) -> Bool {
        myRole(userID: userID) == .initiator ? initiatorAccepted : participantAccepted
    }

    func theirAccepted(userID: UUID) -> Bool {
        myRole(userID: userID) == .initiator ? participantAccepted : initiatorAccepted
    }

    func otherUserID(userID: UUID) -> UUID {
        myRole(userID: userID) == .initiator ? participantID : initiatorID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case initiatorID = "initiator_id"
        case participantID = "participant_id"
        case status
        case initiatorData = "initiator_data"
        case participantData = "participant_data"
        case initiatorOfferSubmitted = "initiator_offer_submitted"
        case participantOfferSubmitted = "participant_offer_submitted"
        case initiatorAccepted = "initiator_accepted"
        case participantAccepted = "participant_accepted"
        case executionLock = "execution_lock"
        case tradeRecordID = "trade_record_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum SessionRole {
    case initiator
    case participant
}

enum TradeSessionError: LocalizedError {
    case notSignedIn
    case missingConfiguration
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to create or view trade sessions."
        case .missingConfiguration: return "Supabase config is missing."
        case .invalidResponse: return "Invalid response from server."
        case .requestFailed(let m): return m
        }
    }
}

@Observable
@MainActor
final class TradeSessionService {
    private let authService: SocialAuthService
    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }

    init(authService: SocialAuthService) {
        self.authService = authService
    }

    func createSession(participantID: UUID) async throws -> TradeSession {
        let userID = try signedInUserID()
        let payload: [String: AnyJSON] = [
            "initiator_id": .string(userID.uuidString),
            "participant_id": .string(participantID.uuidString),
            "status": .string("open"),
            "initiator_data": .object([:]),
            "participant_data": .object([:]),
        ]
        let sessions: [TradeSession] = try await execute(
            path: "/rest/v1/trade_sessions?select=*",
            method: "POST",
            body: .object(payload),
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard let session = sessions.first else { throw TradeSessionError.invalidResponse }
        return session
    }

    func fetchSession(id: UUID) async throws -> TradeSession? {
        let sessions: [TradeSession] = try await execute(
            path: "/rest/v1/trade_sessions?select=*&id=eq.\(id.uuidString)&limit=1",
            method: "GET"
        )
        return sessions.first
    }

    func fetchMyActiveSessions() async throws -> [TradeSession] {
        let userID = try signedInUserID()
        let sessions: [TradeSession] = try await execute(
            path: "/rest/v1/trade_sessions?select=*&or=(initiator_id.eq.\(userID.uuidString),participant_id.eq.\(userID.uuidString))&status=neq.completed&status=neq.cancelled&order=created_at.desc",
            method: "GET"
        )
        return sessions
    }

    func submitOffer(sessionID: UUID, offering: [SessionCardItem], wanting: [SessionCardItem], cash: Double) async throws -> TradeSession {
        let isInitiator = try await isCurrentUserInitiator(sessionID: sessionID)
        let dataPayload: [String: AnyJSON] = [
            "offering": .array(offering.map { $0.toJSON() }),
            "wanting": .array(wanting.map { $0.toJSON() }),
            "cash": .double(cash),
        ]
        var body: [String: AnyJSON] = [:]
        if isInitiator {
            body["initiator_data"] = .object(dataPayload)
            body["initiator_offer_submitted"] = .bool(true)
        } else {
            body["participant_data"] = .object(dataPayload)
            body["participant_offer_submitted"] = .bool(true)
        }

        // If the other side already submitted, advance both_submitted status
        let session = try await fetchSession(id: sessionID)
        let otherSubmitted = isInitiator ? (session?.participantOfferSubmitted ?? false) : (session?.initiatorOfferSubmitted ?? false)
        if otherSubmitted {
            body["status"] = .string("both_submitted")
        }

        let updated: [TradeSession] = try await execute(
            path: "/rest/v1/trade_sessions?id=eq.\(sessionID.uuidString)&select=*",
            method: "PATCH",
            body: .object(body),
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard let result = updated.first else { throw TradeSessionError.invalidResponse }
        return result
    }

    func acceptSession(sessionID: UUID) async throws -> TradeSession {
        let isInitiator = try await isCurrentUserInitiator(sessionID: sessionID)

        var body: [String: AnyJSON] = [:]
        if isInitiator {
            body["initiator_accepted"] = .bool(true)
        } else {
            body["participant_accepted"] = .bool(true)
        }

        let updated: [TradeSession] = try await execute(
            path: "/rest/v1/trade_sessions?id=eq.\(sessionID.uuidString)&select=*",
            method: "PATCH",
            body: .object(body),
            extraHeaders: ["Prefer": "return=representation"]
        )
        guard let result = updated.first else { throw TradeSessionError.invalidResponse }
        return result
    }

    /// Try to acquire the execution lock. Returns true if we got it.
    func acquireExecutionLock(sessionID: UUID) async throws -> Bool {
        let lockID = UUID()
        let updated: [TradeSession] = try await execute(
            path: "/rest/v1/trade_sessions?id=eq.\(sessionID.uuidString)&execution_lock=is.null&select=*",
            method: "PATCH",
            body: .object(["execution_lock": .string(lockID.uuidString), "status": .string("executing")]),
            extraHeaders: ["Prefer": "return=representation"]
        )
        return !updated.isEmpty
    }

    func markCompleted(sessionID: UUID, tradeRecordID: UUID) async throws {
        _ = try await execute(
            path: "/rest/v1/trade_sessions?id=eq.\(sessionID.uuidString)&select=id",
            method: "PATCH",
            body: .object([
                "status": .string("completed"),
                "trade_record_id": .string(tradeRecordID.uuidString),
            ]),
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptySessionResponse
    }

    func cancelSession(sessionID: UUID) async throws {
        _ = try await execute(
            path: "/rest/v1/trade_sessions?id=eq.\(sessionID.uuidString)&select=id",
            method: "PATCH",
            body: .object(["status": .string("cancelled")]),
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptySessionResponse
    }

    // MARK: - Helpers

    private func isCurrentUserInitiator(sessionID: UUID) async throws -> Bool {
        let userID = try signedInUserID()
        guard let session = try await fetchSession(id: sessionID) else {
            throw TradeSessionError.requestFailed("Session not found")
        }
        return session.initiatorID == userID
    }

    private func signedInUserID() throws -> UUID {
        switch authService.authState {
        case .signedOut: throw TradeSessionError.notSignedIn
        case .signedIn(let id, _): return id
        }
    }

    private func signedInAccessToken() throws -> String {
        guard let token = authService.accessToken, !token.isEmpty else {
            throw TradeSessionError.notSignedIn
        }
        return token
    }

    // MARK: - Network

    private func execute<T: Decodable>(
        path: String,
        method: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        try await execute(path: path, method: method, body: nil as AnyJSON?, extraHeaders: extraHeaders)
    }

    private func execute<T: Decodable>(
        path: String,
        method: String,
        body: AnyJSON?,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        guard let baseURL, !publishableKey.isEmpty else {
            throw TradeSessionError.missingConfiguration
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw TradeSessionError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try signedInAccessToken())", forHTTPHeaderField: "Authorization")
        for (header, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        if let body {
            request.httpBody = try JSONEncoder.socialSessionJSON.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TradeSessionError.invalidResponse
        }
        if isExpiredJWT(statusCode: http.statusCode, data: data) {
            await authService.restoreSession()
            if let refreshed = authService.accessToken, !refreshed.isEmpty {
                request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw TradeSessionError.invalidResponse
                }
                guard (200..<300).contains(retryHTTP.statusCode) else {
                    throw TradeSessionError.requestFailed("Request failed with status \(retryHTTP.statusCode).")
                }
                if T.self == EmptySessionResponse.self { return EmptySessionResponse() as! T }
                return try JSONDecoder.socialSessionJSON.decode(T.self, from: retryData)
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TradeSessionError.requestFailed("Request failed with status \(http.statusCode).")
        }
        if T.self == EmptySessionResponse.self { return EmptySessionResponse() as! T }
        return try JSONDecoder.socialSessionJSON.decode(T.self, from: data)
    }

    private func isExpiredJWT(statusCode: Int, data: Data) -> Bool {
        guard statusCode == 401 else { return false }
        guard let payload = try? JSONDecoder.socialSessionJSON.decode(APIErrorPayload.self, from: data) else { return false }
        let msg = (payload.message ?? payload.hint ?? "").lowercased()
        return msg.contains("jwt") && msg.contains("expired")
    }
}

private struct EmptySessionResponse: Decodable {}

private struct APIErrorPayload: Decodable {
    let message: String?
    let hint: String?
}

enum AnyJSON: Codable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case object([String: AnyJSON])
    case array([AnyJSON])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode([String: AnyJSON].self) { self = .object(v); return }
        if let v = try? container.decode([AnyJSON].self) { self = .array(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown JSON type")
    }
}

extension SessionCardItem {
    func toJSON() -> AnyJSON {
        .object([
            "cardID": .string(cardID),
            "variantKey": .string(variantKey),
            "quantity": .double(Double(quantity)),
        ])
    }
}

private extension JSONDecoder {
    static var socialSessionJSON: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

private extension JSONEncoder {
    static var socialSessionJSON: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
