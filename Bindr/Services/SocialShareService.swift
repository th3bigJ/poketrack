import Foundation
import Observation

@Observable
@MainActor
final class SocialShareService {
    enum SocialShareError: LocalizedError {
        case notSignedIn
        case missingConfiguration
        case invalidResponse
        case missingModelContext
        case freeTierLimitReached
        case deckSharingRequiresPremium
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in first to share social content."
            case .missingConfiguration:
                return "Supabase social config is missing from Info.plist."
            case .invalidResponse:
                return "Could not parse shared content data from Supabase."
            case .missingModelContext:
                return "App data context is not ready yet."
            case .freeTierLimitReached:
                return "Free tier allows publishing one binder and one wishlist. Upgrade to Premium to publish everything."
            case .deckSharingRequiresPremium:
                return "Deck sharing is a premium feature."
            case .requestFailed(let message):
                return message
            }
        }
    }

    struct ShareSnapshot: Sendable {
        let sharedContent: SharedContent?
        let title: String
        let description: String
        let visibility: SharedContentVisibility
        let includeValue: Bool
        let isPublished: Bool
    }

    private struct APIErrorPayload: Decodable {
        let message: String?
        let hint: String?
    }

    private struct SharedContentUpsertRequest: Encodable {
        let ownerID: UUID
        let contentType: SharedContentType
        let title: String
        let description: String?
        let visibility: SharedContentVisibility
        let payload: [String: JSONValue]
        let includeValue: Bool
        let cardCount: Int
        let brand: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case ownerID = "owner_id"
            case contentType = "content_type"
            case title
            case description
            case visibility
            case payload
            case includeValue = "include_value"
            case cardCount = "card_count"
            case brand
            case updatedAt = "updated_at"
        }
    }

    private struct WishlistMatchRequest: Encodable {
        let contentID: UUID
        let cardID: String
        let senderID: UUID
        let variantKey: String

        enum CodingKeys: String, CodingKey {
            case contentID = "content_id"
            case cardID = "card_id"
            case senderID = "sender_id"
            case variantKey = "variant_key"
        }
    }

    private enum LocalKey: Hashable {
        case binder(UUID)
        case deck(UUID)
        case wishlist
    }

    private struct EncodedPayload {
        let payload: [String: JSONValue]
        let title: String
        let cardCount: Int
        let brand: String?
        let localContentID: String
    }

    private struct BinderSlotSnapshot: Sendable {
        let cardID: String
        let variantKey: String
        let cardName: String
    }

    private struct BinderSyncSnapshot: Sendable {
        let id: UUID
        let title: String
        let brandRawValue: String
        let slots: [BinderSlotSnapshot]
    }

    private struct DeckCardSnapshot: Sendable {
        let cardID: String
        let variantKey: String
        let cardName: String
        let quantity: Int
    }

    private struct DeckSyncSnapshot: Sendable {
        let id: UUID
        let title: String
        let brandRawValue: String
        let formatDisplayName: String
        let cards: [DeckCardSnapshot]
    }

    private struct WishlistItemSnapshot: Sendable {
        let cardID: String
        let variantKey: String
        let notes: String
    }

    private let authService: SocialAuthService
    private let storeService: StoreKitService
    private let cardDataService: CardDataService
    private let pricingService: PricingService

    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }

    private var pendingSyncTasks: [LocalKey: Task<Void, Never>] = [:]

    init(
        authService: SocialAuthService,
        storeService: StoreKitService,
        cardDataService: CardDataService,
        pricingService: PricingService
    ) {
        self.authService = authService
        self.storeService = storeService
        self.cardDataService = cardDataService
        self.pricingService = pricingService
    }

    func fetchMySharedContent() async throws -> [SharedContent] {
        let userID = try signedInUserID()
        let path = "/rest/v1/shared_content?select=*&owner_id=eq.\(userID.uuidString)&order=updated_at.desc"
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    func fetchSharedContent(ownerID: UUID) async throws -> [SharedContent] {
        let path = "/rest/v1/shared_content?select=*&owner_id=eq.\(ownerID.uuidString)&order=updated_at.desc"
        return try await execute(path: path, method: "GET", accessToken: try signedInAccessToken())
    }

    func shareSnapshot(for binder: Binder) async throws -> ShareSnapshot {
        let existing = try await fetchMine(type: .binder, localContentID: binder.id.uuidString)
        return ShareSnapshot(
            sharedContent: existing,
            title: existing?.title ?? binder.title,
            description: existing?.description ?? "",
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false,
            isPublished: existing != nil
        )
    }

    func shareSnapshot(for deck: Deck) async throws -> ShareSnapshot {
        let existing = try await fetchMine(type: .deck, localContentID: deck.id.uuidString)
        return ShareSnapshot(
            sharedContent: existing,
            title: existing?.title ?? deck.title,
            description: existing?.description ?? "",
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false,
            isPublished: existing != nil
        )
    }

    func shareSnapshotForWishlist() async throws -> ShareSnapshot {
        let existing = try await fetchMine(type: .wishlist, localContentID: "wishlist")
        return ShareSnapshot(
            sharedContent: existing,
            title: existing?.title ?? "Wishlist",
            description: existing?.description ?? "",
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false,
            isPublished: existing != nil
        )
    }

    func publishBinder(
        _ binder: Binder,
        title: String,
        description: String,
        visibility: SharedContentVisibility,
        includeValue: Bool
    ) async throws -> SharedContent {
        try await enforceFreeTierLimitIfNeeded(for: .binder, localContentID: binder.id.uuidString)
        let encoded = try await encodeBinderPayload(binder, includeValue: includeValue)
        return try await upsertSharedContent(
            type: .binder,
            localContentID: encoded.localContentID,
            encoded: encoded,
            title: normalizedTitle(title, fallback: binder.title),
            description: normalizedDescription(description),
            visibility: visibility,
            includeValue: includeValue
        )
    }

    func publishDeck(
        _ deck: Deck,
        title: String,
        description: String,
        visibility: SharedContentVisibility,
        includeValue: Bool
    ) async throws -> SharedContent {
        guard storeService.isPremium else {
            throw SocialShareError.deckSharingRequiresPremium
        }
        let encoded = try await encodeDeckPayload(deck, includeValue: includeValue)
        return try await upsertSharedContent(
            type: .deck,
            localContentID: encoded.localContentID,
            encoded: encoded,
            title: normalizedTitle(title, fallback: deck.title),
            description: normalizedDescription(description),
            visibility: visibility,
            includeValue: includeValue
        )
    }

    func publishWishlist(
        title: String,
        description: String,
        visibility: SharedContentVisibility,
        includeValue: Bool,
        wishlistItems: [WishlistItem]
    ) async throws -> SharedContent {
        let encoded = try await encodeWishlistPayload(wishlistItems, includeValue: includeValue)
        return try await upsertSharedContent(
            type: .wishlist,
            localContentID: encoded.localContentID,
            encoded: encoded,
            title: normalizedTitle(title, fallback: "Wishlist"),
            description: normalizedDescription(description),
            visibility: visibility,
            includeValue: includeValue
        )
    }

    func unpublishBinder(_ binder: Binder) async throws {
        try await unpublish(type: .binder, localContentID: binder.id.uuidString)
    }

    func unpublishDeck(_ deck: Deck) async throws {
        try await unpublish(type: .deck, localContentID: deck.id.uuidString)
    }

    func unpublishWishlist() async throws {
        try await unpublish(type: .wishlist, localContentID: "wishlist")
    }

    func scheduleAutoSync(binder: Binder) {
        let snapshot = BinderSyncSnapshot(
            id: binder.id,
            title: binder.title,
            brandRawValue: binder.tcgBrand.rawValue,
            slots: binder.slotList.map {
                BinderSlotSnapshot(cardID: $0.cardID, variantKey: $0.variantKey, cardName: $0.cardName)
            }
        )
        scheduleAutoSync(for: .binder(binder.id)) { [weak self] in
            guard let self else { return }
            try await self.syncIfPublished(binderSnapshot: snapshot)
        }
    }

    func scheduleAutoSync(deck: Deck) {
        let snapshot = DeckSyncSnapshot(
            id: deck.id,
            title: deck.title,
            brandRawValue: deck.tcgBrand.rawValue,
            formatDisplayName: deck.deckFormat.displayName,
            cards: deck.cardList.map {
                DeckCardSnapshot(cardID: $0.cardID, variantKey: $0.variantKey, cardName: $0.cardName, quantity: $0.quantity)
            }
        )
        scheduleAutoSync(for: .deck(deck.id)) { [weak self] in
            guard let self else { return }
            try await self.syncIfPublished(deckSnapshot: snapshot)
        }
    }

    func scheduleAutoSyncWishlist(items: [WishlistItem]) {
        let snapshots = items.map {
            WishlistItemSnapshot(cardID: $0.cardID, variantKey: $0.variantKey, notes: $0.notes)
        }
        scheduleAutoSync(for: .wishlist) { [weak self] in
            guard let self else { return }
            try await self.syncIfPublishedWishlist(itemSnapshots: snapshots)
        }
    }

    func reconcilePublishedContent(localBinderIDs: Set<UUID>, localDeckIDs: Set<UUID>, hasWishlist: Bool) async throws {
        let mine = try await fetchMySharedContent()
        for entry in mine {
            guard let localID = entry.localContentID else { continue }
            switch entry.contentType {
            case .binder:
                guard let uuid = UUID(uuidString: localID), !localBinderIDs.contains(uuid) else { continue }
                try await deleteSharedContent(id: entry.id)
            case .deck:
                guard let uuid = UUID(uuidString: localID), !localDeckIDs.contains(uuid) else { continue }
                try await deleteSharedContent(id: entry.id)
            case .wishlist:
                if !hasWishlist {
                    try await deleteSharedContent(id: entry.id)
                }
            case .pull, .dailyDigest:
                // Server-generated events — never delete locally
                break
            }
        }
    }

    func reconcileDeletedBinders(localBinderIDs: Set<UUID>) async throws {
        let mine = try await fetchMySharedContent()
        for entry in mine where entry.contentType == .binder {
            guard let localID = entry.localContentID, let uuid = UUID(uuidString: localID) else { continue }
            if !localBinderIDs.contains(uuid) {
                try await deleteSharedContent(id: entry.id)
            }
        }
    }

    func reconcileDeletedDecks(localDeckIDs: Set<UUID>) async throws {
        let mine = try await fetchMySharedContent()
        for entry in mine where entry.contentType == .deck {
            guard let localID = entry.localContentID, let uuid = UUID(uuidString: localID) else { continue }
            if !localDeckIDs.contains(uuid) {
                try await deleteSharedContent(id: entry.id)
            }
        }
    }

    func reconcileDeletedWishlist(hasWishlist: Bool) async throws {
        guard !hasWishlist else { return }
        let mine = try await fetchMySharedContent()
        for entry in mine where entry.contentType == .wishlist {
            try await deleteSharedContent(id: entry.id)
        }
    }

    func sendWishlistMatch(contentID: UUID, cardID: String, variantKey: String) async throws {
        let payload = WishlistMatchRequest(
            contentID: contentID,
            cardID: cardID,
            senderID: try signedInUserID(),
            variantKey: variantKey
        )
        _ = try await execute(
            path: "/rest/v1/wishlist_matches",
            method: "POST",
            accessToken: try signedInAccessToken(),
            body: payload,
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptyResponse
    }

    private func syncIfPublished(binder: Binder) async throws {
        let existing = try await fetchMine(type: .binder, localContentID: binder.id.uuidString)
        guard existing != nil else { return }
        _ = try await publishBinder(
            binder,
            title: existing?.title ?? binder.title,
            description: existing?.description ?? "",
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false
        )
    }

    private func syncIfPublished(deck: Deck) async throws {
        let existing = try await fetchMine(type: .deck, localContentID: deck.id.uuidString)
        guard existing != nil else { return }
        _ = try await publishDeck(
            deck,
            title: existing?.title ?? deck.title,
            description: existing?.description ?? "",
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false
        )
    }

    private func syncIfPublishedWishlist(items: [WishlistItem]) async throws {
        let existing = try await fetchMine(type: .wishlist, localContentID: "wishlist")
        guard existing != nil else { return }
        _ = try await publishWishlist(
            title: existing?.title ?? "Wishlist",
            description: existing?.description ?? "",
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false,
            wishlistItems: items
        )
    }

    private func syncIfPublished(binderSnapshot: BinderSyncSnapshot) async throws {
        let localID = binderSnapshot.id.uuidString
        let existing = try await fetchMine(type: .binder, localContentID: localID)
        guard existing != nil else { return }
        let encoded = try await encodeBinderPayload(binderSnapshot, includeValue: existing?.includeValue ?? false)
        _ = try await upsertSharedContent(
            type: .binder,
            localContentID: encoded.localContentID,
            encoded: encoded,
            title: existing?.title ?? binderSnapshot.title,
            description: existing?.description,
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false
        )
    }

    private func syncIfPublished(deckSnapshot: DeckSyncSnapshot) async throws {
        let localID = deckSnapshot.id.uuidString
        let existing = try await fetchMine(type: .deck, localContentID: localID)
        guard existing != nil else { return }
        let encoded = try await encodeDeckPayload(deckSnapshot, includeValue: existing?.includeValue ?? false)
        _ = try await upsertSharedContent(
            type: .deck,
            localContentID: encoded.localContentID,
            encoded: encoded,
            title: existing?.title ?? deckSnapshot.title,
            description: existing?.description,
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false
        )
    }

    private func syncIfPublishedWishlist(itemSnapshots: [WishlistItemSnapshot]) async throws {
        let existing = try await fetchMine(type: .wishlist, localContentID: "wishlist")
        guard existing != nil else { return }
        let encoded = try await encodeWishlistPayload(itemSnapshots, includeValue: existing?.includeValue ?? false)
        _ = try await upsertSharedContent(
            type: .wishlist,
            localContentID: encoded.localContentID,
            encoded: encoded,
            title: existing?.title ?? "Wishlist",
            description: existing?.description,
            visibility: existing?.visibility ?? .friends,
            includeValue: existing?.includeValue ?? false
        )
    }

    private func scheduleAutoSync(for key: LocalKey, operation: @escaping @Sendable () async throws -> Void) {
        pendingSyncTasks[key]?.cancel()
        pendingSyncTasks[key] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                try await operation()
            } catch {
                // Intentionally non-fatal: failed auto-sync can be retried from the next local change.
            }
            self?.pendingSyncTasks[key] = nil
        }
    }

    private func upsertSharedContent(
        type: SharedContentType,
        localContentID: String,
        encoded: EncodedPayload,
        title: String,
        description: String?,
        visibility: SharedContentVisibility,
        includeValue: Bool
    ) async throws -> SharedContent {
        let userID = try signedInUserID()
        let accessToken = try signedInAccessToken()
        let existing = try await fetchMine(type: type, localContentID: localContentID)
        let payload = SharedContentUpsertRequest(
            ownerID: userID,
            contentType: type,
            title: title,
            description: description,
            visibility: visibility,
            payload: encoded.payload,
            includeValue: includeValue,
            cardCount: encoded.cardCount,
            brand: encoded.brand,
            updatedAt: Date()
        )
        if let existing {
            let path = "/rest/v1/shared_content?id=eq.\(existing.id.uuidString)&owner_id=eq.\(userID.uuidString)&select=*"
            let updated: [SharedContent] = try await execute(
                path: path,
                method: "PATCH",
                accessToken: accessToken,
                body: payload,
                extraHeaders: ["Prefer": "return=representation"]
            )
            return try updated.first.unwrapOrThrow(SocialShareError.invalidResponse)
        } else {
            let created: [SharedContent] = try await execute(
                path: "/rest/v1/shared_content?select=*",
                method: "POST",
                accessToken: accessToken,
                body: payload,
                extraHeaders: ["Prefer": "return=representation"]
            )
            return try created.first.unwrapOrThrow(SocialShareError.invalidResponse)
        }
    }

    private func unpublish(type: SharedContentType, localContentID: String) async throws {
        guard let existing = try await fetchMine(type: type, localContentID: localContentID) else { return }
        try await deleteSharedContent(id: existing.id)
    }

    private func deleteSharedContent(id: UUID) async throws {
        let userID = try signedInUserID()
        _ = try await execute(
            path: "/rest/v1/shared_content?id=eq.\(id.uuidString)&owner_id=eq.\(userID.uuidString)",
            method: "DELETE",
            accessToken: try signedInAccessToken(),
            extraHeaders: ["Prefer": "return=minimal"]
        ) as EmptyResponse
    }

    private func fetchMine(type: SharedContentType, localContentID: String) async throws -> SharedContent? {
        let mine = try await fetchMySharedContent()
        return mine.first(where: { row in
            row.contentType == type && row.localContentID == localContentID
        })
    }

    private func enforceFreeTierLimitIfNeeded(for type: SharedContentType, localContentID: String) async throws {
        guard !storeService.isPremium else { return }
        if type == .deck {
            throw SocialShareError.deckSharingRequiresPremium
        }
        let mine = try await fetchMySharedContent()
        switch type {
        case .binder:
            let publishedBinders = mine.filter { $0.contentType == .binder && $0.localContentID != localContentID }
            if !publishedBinders.isEmpty {
                throw SocialShareError.freeTierLimitReached
            }
        case .wishlist:
            break
        case .deck:
            throw SocialShareError.deckSharingRequiresPremium
        case .pull, .dailyDigest:
            // Server-generated — no limit enforcement needed
            break
        }
    }

    private func encodeWishlistPayload(_ items: [WishlistItem], includeValue: Bool) async throws -> EncodedPayload {
        var rows: [[String: JSONValue]] = []
        var totalValue: Double = 0
        for item in items {
            var row: [String: JSONValue] = [
                "cardID": .string(item.cardID),
                "variantKey": .string(item.variantKey)
            ]
            if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                row["notes"] = .string(item.notes)
            }
            if let card = await cardDataService.loadCard(masterCardId: item.cardID) {
                row["cardName"] = .string(card.cardName)
                if includeValue, let value = await pricingService.usdPriceForVariant(for: card, variantKey: item.variantKey) {
                    row["market_value_usd"] = .number(value)
                    totalValue += value
                }
            }
            rows.append(row)
        }
        var payload: [String: JSONValue] = [
            "payload_version": .number(1),
            "generated_at": .string(ISO8601DateFormatter().string(from: Date())),
            "local_content_id": .string("wishlist"),
            "items": .array(rows.map(JSONValue.object))
        ]
        if includeValue {
            payload["market_value_usd"] = .number(totalValue)
        }
        return EncodedPayload(
            payload: payload,
            title: "Wishlist",
            cardCount: rows.count,
            brand: nil,
            localContentID: "wishlist"
        )
    }

    private func encodeWishlistPayload(_ itemSnapshots: [WishlistItemSnapshot], includeValue: Bool) async throws -> EncodedPayload {
        var rows: [[String: JSONValue]] = []
        var totalValue: Double = 0
        for item in itemSnapshots {
            var row: [String: JSONValue] = [
                "cardID": .string(item.cardID),
                "variantKey": .string(item.variantKey)
            ]
            if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                row["notes"] = .string(item.notes)
            }
            if let card = await cardDataService.loadCard(masterCardId: item.cardID) {
                row["cardName"] = .string(card.cardName)
                if includeValue, let value = await pricingService.usdPriceForVariant(for: card, variantKey: item.variantKey) {
                    row["market_value_usd"] = .number(value)
                    totalValue += value
                }
            }
            rows.append(row)
        }
        var payload: [String: JSONValue] = [
            "payload_version": .number(1),
            "generated_at": .string(ISO8601DateFormatter().string(from: Date())),
            "local_content_id": .string("wishlist"),
            "items": .array(rows.map(JSONValue.object))
        ]
        if includeValue {
            payload["market_value_usd"] = .number(totalValue)
        }
        return EncodedPayload(
            payload: payload,
            title: "Wishlist",
            cardCount: rows.count,
            brand: nil,
            localContentID: "wishlist"
        )
    }

    private func encodeBinderPayload(_ binder: Binder, includeValue: Bool) async throws -> EncodedPayload {
        var rows: [[String: JSONValue]] = []
        var totalValue: Double = 0
        for slot in binder.slotList {
            var row: [String: JSONValue] = [
                "cardID": .string(slot.cardID),
                "variantKey": .string(slot.variantKey),
                "quantity": .number(1),
                "cardName": .string(slot.cardName)
            ]
            if includeValue,
               let card = await cardDataService.loadCard(masterCardId: slot.cardID),
               let value = await pricingService.usdPriceForVariant(for: card, variantKey: slot.variantKey) {
                row["market_value_usd"] = .number(value)
                totalValue += value
            }
            rows.append(row)
        }
        var payload: [String: JSONValue] = [
            "payload_version": .number(1),
            "generated_at": .string(ISO8601DateFormatter().string(from: Date())),
            "local_content_id": .string(binder.id.uuidString),
            "brand": .string(binder.tcgBrand.rawValue),
            "colour": .string(binder.colour),
            "texture": .string(binder.textureKind.rawValue),
            "seed": .number(Double(binder.textureSeed)),
            "items": .array(rows.map(JSONValue.object))
        ]
        if includeValue {
            payload["market_value_usd"] = .number(totalValue)
        }
        return EncodedPayload(
            payload: payload,
            title: binder.title,
            cardCount: rows.count,
            brand: binder.tcgBrand.rawValue,
            localContentID: binder.id.uuidString
        )
    }

    private func encodeBinderPayload(_ snapshot: BinderSyncSnapshot, includeValue: Bool) async throws -> EncodedPayload {
        var rows: [[String: JSONValue]] = []
        var totalValue: Double = 0
        for slot in snapshot.slots {
            var row: [String: JSONValue] = [
                "cardID": .string(slot.cardID),
                "variantKey": .string(slot.variantKey),
                "quantity": .number(1),
                "cardName": .string(slot.cardName)
            ]
            if includeValue,
               let card = await cardDataService.loadCard(masterCardId: slot.cardID),
               let value = await pricingService.usdPriceForVariant(for: card, variantKey: slot.variantKey) {
                row["market_value_usd"] = .number(value)
                totalValue += value
            }
            rows.append(row)
        }
        var payload: [String: JSONValue] = [
            "payload_version": .number(1),
            "generated_at": .string(ISO8601DateFormatter().string(from: Date())),
            "local_content_id": .string(snapshot.id.uuidString),
            "brand": .string(snapshot.brandRawValue),
            "items": .array(rows.map(JSONValue.object))
        ]
        // Note: snapshot doesn't have colour/texture yet, but we should add it to snapshot if we want it to sync
        if includeValue {
            payload["market_value_usd"] = .number(totalValue)
        }
        return EncodedPayload(
            payload: payload,
            title: snapshot.title,
            cardCount: rows.count,
            brand: snapshot.brandRawValue,
            localContentID: snapshot.id.uuidString
        )
    }

    private func encodeDeckPayload(_ deck: Deck, includeValue: Bool) async throws -> EncodedPayload {
        var rows: [[String: JSONValue]] = []
        var totalCardCount = 0
        var totalValue: Double = 0
        for entry in deck.cardList {
            totalCardCount += entry.quantity
            var row: [String: JSONValue] = [
                "cardID": .string(entry.cardID),
                "variantKey": .string(entry.variantKey),
                "quantity": .number(Double(entry.quantity)),
                "cardName": .string(entry.cardName)
            ]
            if includeValue,
               let card = await cardDataService.loadCard(masterCardId: entry.cardID),
               let unit = await pricingService.usdPriceForVariant(for: card, variantKey: entry.variantKey) {
                let line = unit * Double(entry.quantity)
                row["market_value_usd"] = .number(line)
                totalValue += line
            }
            rows.append(row)
        }
        var payload: [String: JSONValue] = [
            "payload_version": .number(1),
            "generated_at": .string(ISO8601DateFormatter().string(from: Date())),
            "local_content_id": .string(deck.id.uuidString),
            "brand": .string(deck.tcgBrand.rawValue),
            "format": .string(deck.deckFormat.displayName),
            "cards": .array(rows.map(JSONValue.object))
        ]
        if includeValue {
            payload["market_value_usd"] = .number(totalValue)
        }
        return EncodedPayload(
            payload: payload,
            title: deck.title,
            cardCount: totalCardCount,
            brand: deck.tcgBrand.rawValue,
            localContentID: deck.id.uuidString
        )
    }

    private func encodeDeckPayload(_ snapshot: DeckSyncSnapshot, includeValue: Bool) async throws -> EncodedPayload {
        var rows: [[String: JSONValue]] = []
        var totalCardCount = 0
        var totalValue: Double = 0
        for entry in snapshot.cards {
            totalCardCount += entry.quantity
            var row: [String: JSONValue] = [
                "cardID": .string(entry.cardID),
                "variantKey": .string(entry.variantKey),
                "quantity": .number(Double(entry.quantity)),
                "cardName": .string(entry.cardName)
            ]
            if includeValue,
               let card = await cardDataService.loadCard(masterCardId: entry.cardID),
               let unit = await pricingService.usdPriceForVariant(for: card, variantKey: entry.variantKey) {
                let line = unit * Double(entry.quantity)
                row["market_value_usd"] = .number(line)
                totalValue += line
            }
            rows.append(row)
        }
        var payload: [String: JSONValue] = [
            "payload_version": .number(1),
            "generated_at": .string(ISO8601DateFormatter().string(from: Date())),
            "local_content_id": .string(snapshot.id.uuidString),
            "brand": .string(snapshot.brandRawValue),
            "format": .string(snapshot.formatDisplayName),
            "cards": .array(rows.map(JSONValue.object))
        ]
        if includeValue {
            payload["market_value_usd"] = .number(totalValue)
        }
        return EncodedPayload(
            payload: payload,
            title: snapshot.title,
            cardCount: totalCardCount,
            brand: snapshot.brandRawValue,
            localContentID: snapshot.id.uuidString
        )
    }

    private func normalizedTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallback
        }
        return trimmed
    }

    private func normalizedDescription(_ description: String) -> String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func signedInUserID() throws -> UUID {
        switch authService.authState {
        case .signedOut:
            throw SocialShareError.notSignedIn
        case .signedIn(let userID, _):
            return userID
        }
    }

    private func signedInAccessToken() throws -> String {
        guard let token = authService.accessToken, !token.isEmpty else {
            throw SocialShareError.notSignedIn
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
            throw SocialShareError.missingConfiguration
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SocialShareError.invalidResponse
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
            request.httpBody = try JSONEncoder.socialJSON.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SocialShareError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder.socialJSON.decode(APIErrorPayload.self, from: data) {
                throw SocialShareError.requestFailed(payload.message ?? payload.hint ?? "Supabase request failed with status \(http.statusCode).")
            }
            throw SocialShareError.requestFailed("Supabase request failed with status \(http.statusCode).")
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        if data.isEmpty {
            throw SocialShareError.invalidResponse
        }
        return try JSONDecoder.socialJSON.decode(T.self, from: data)
    }
}

private struct EmptyResponse: Decodable {}

private extension JSONDecoder {
    static var socialJSON: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var socialJSON: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension Optional {
    func unwrapOrThrow(_ error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}
