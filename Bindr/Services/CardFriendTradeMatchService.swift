import Foundation
import Observation

/// Resolves which friends have or want a card by reading their shared collection snapshots.
@Observable
@MainActor
final class CardFriendTradeMatchService {
    private(set) var isLoadingCardID: String?

    func tradeContexts(
        for card: Card,
        services: AppServices,
        onTrade: @escaping (Card, AppServices.TradePrefillSide) -> Void
    ) async -> [CardTradeContext] {
        guard case .signedIn = services.socialAuth.authState else { return [] }

        let cardID = card.masterCardId
        isLoadingCardID = cardID
        defer {
            if isLoadingCardID == cardID {
                isLoadingCardID = nil
            }
        }

        let lookupKeys = Set(Self.aliasCardIDs(for: card))
        guard !lookupKeys.isEmpty else { return [] }

        let friends = (try? await services.socialFriend.fetchFriends()) ?? []
        guard !friends.isEmpty else { return [] }

        var friendsWhoWant: [SocialProfile] = []
        var friendsWhoHave: [SocialProfile] = []

        await withTaskGroup(of: (SocialProfile, Bool, Bool).self) { group in
            for friend in friends {
                group.addTask { @MainActor in
                    await Self.evaluateFriend(
                        friend,
                        lookupKeys: lookupKeys,
                        services: services
                    )
                }
            }
            for await (friend, wants, has) in group {
                if wants {
                    Self.appendFriend(friend, to: &friendsWhoWant)
                }
                if has {
                    Self.appendFriend(friend, to: &friendsWhoHave)
                }
            }
        }

        return Self.buildContexts(
            friendsWhoWant: friendsWhoWant,
            friendsWhoHave: friendsWhoHave,
            onTrade: { onTrade(card, $0) }
        )
    }

    private static func evaluateFriend(
        _ friend: SocialProfile,
        lookupKeys: Set<String>,
        services: AppServices
    ) async -> (SocialProfile, Bool, Bool) {
        guard let snapshot = try? await services.collectionSync.fetchFriendCollection(userID: friend.id) else {
            return (friend, false, false)
        }

        var wants = false
        for entry in snapshot.wishlist where !entry.cardID.isEmpty {
            if await entryMatchesCard(entryCardID: entry.cardID, lookupKeys: lookupKeys, services: services) {
                wants = true
                break
            }
        }

        var has = false
        for entry in snapshot.collection where !entry.cardID.isEmpty && entry.qty > 0 {
            if await entryMatchesCard(entryCardID: entry.cardID, lookupKeys: lookupKeys, services: services) {
                has = true
                break
            }
        }

        return (friend, wants, has)
    }

    private static func entryMatchesCard(
        entryCardID: String,
        lookupKeys: Set<String>,
        services: AppServices
    ) async -> Bool {
        if lookupKeys.contains(normalizeCardID(entryCardID)) {
            return true
        }
        guard let resolved = await services.cardData.loadCard(masterCardId: entryCardID) else {
            return false
        }
        return !lookupKeys.isDisjoint(with: aliasCardIDs(for: resolved))
    }

    private static func buildContexts(
        friendsWhoWant: [SocialProfile],
        friendsWhoHave: [SocialProfile],
        onTrade: @escaping (AppServices.TradePrefillSide) -> Void
    ) -> [CardTradeContext] {
        var contexts: [CardTradeContext] = []

        if !friendsWhoWant.isEmpty {
            let message: String = {
                if friendsWhoWant.count == 1 {
                    return "\(friendsWhoWant[0].shortDisplayName) wants this card"
                }
                return "\(friendsWhoWant.count) people want this card"
            }()
            contexts.append(CardTradeContext(message: message) { _ in onTrade(.mySide) })
        }

        if !friendsWhoHave.isEmpty {
            let message: String = {
                if friendsWhoHave.count == 1 {
                    return "\(friendsWhoHave[0].shortDisplayName) has this card"
                }
                return "\(friendsWhoHave.count) people have this card"
            }()
            contexts.append(CardTradeContext(message: message) { _ in onTrade(.theirSide) })
        }

        return contexts
    }

    private static func appendFriend(_ friend: SocialProfile, to list: inout [SocialProfile]) {
        guard !list.contains(where: { $0.id == friend.id }) else { return }
        list.append(friend)
    }

    private static func aliasCardIDs(for card: Card) -> Set<String> {
        normalizedAliasSet(card.masterCardId, card.externalId, card.tcgdex_id, card.localId)
    }

    private static func normalizedAliasSet(_ values: String?...) -> Set<String> {
        Set(
            values
                .compactMap { $0 }
                .map { normalizeCardID($0) }
                .filter { !$0.isEmpty }
        )
    }

    private static func normalizeCardID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension AppServices {
    func launchTradeFromCardDetail(cardID: String, preferredSide: TradePrefillSide) {
        pendingTradeSeed = PendingTradeSeed(cardID: cardID, preferredSide: preferredSide)
        Haptics.mediumImpact()
        if let url = URL(string: "bindr://social/friends") {
            socialPush.queueDeepLink(url: url)
        }
    }
}
