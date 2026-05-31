import Foundation

// MARK: - FeaturedHeroCardsLoader
//
// Picks up to 3 visually-striking real cards from the catalog to feed
// the `FloatingCardStack` hero on `SocialLandingView` and
// `OnboardingSocialDiscoveryView`.
//
// Curation strategy:
//   1. Start with the user's currently-selected brand and the newest
//      set we know about (`services.cardData.sets` is sorted newest-first).
//   2. Prefer the most marquee rarities — Hyper Rare, Special Illustration
//      Rare, Illustration Rare, Secret Rare, Manga Rare, etc. These are
//      the cards collectors actually chase, so they land emotionally.
//   3. Backfill with anything that has an image URL, so the hero never
//      shows fewer than 3 cards on a populated catalog.
//
// Failure modes are intentionally silent — if the catalog isn't ready
// yet (very fresh install, mid-bootstrap), the loader returns `[]` and
// the floating-stack falls back to its stylised gradient placeholders.

@MainActor
enum FeaturedHeroCardsLoader {
    /// Rarity strings, ordered by visual impact. Match is case-insensitive
    /// + substring (`localizedCaseInsensitiveContains`) so we catch
    /// "Special Illustration Rare", "Illustration Rare", "Trainer
    /// Gallery", etc. without listing every dataset variant.
    private static let priorityRarityFragments: [String] = [
        "hyper rare",
        "special illustration",
        "illustration rare",
        "ultra rare",
        "secret rare",
        "rainbow rare",
        "alt art",
        "alternate art",
        "manga rare",
        "super rare",
        "double rare"
    ]

    /// Returns up to `limit` curated cards. Safe to call before the
    /// catalog is ready — emits `[]` instead of throwing.
    static func loadFeaturedCards(
        services: AppServices,
        limit: Int = 3
    ) async -> [Card] {
        let sets = services.cardData.sets
        // Walk newest → older until we have enough picks. Most catalogs
        // satisfy the request from the newest set alone; the loop is a
        // safety net for sparse / freshly-cleared caches.
        var picks: [Card] = []
        var seen: Set<String> = []

        for set in sets.prefix(6) {
            let setCards = await services.cardData.loadCards(forSetCode: set.setCode)
            let curated = curate(cards: setCards, excluding: seen)
            for card in curated {
                guard picks.count < limit else { break }
                picks.append(card)
                seen.insert(card.masterCardId)
            }
            if picks.count >= limit { break }
        }

        return picks
    }

    private static func curate(cards: [Card], excluding seen: Set<String>) -> [Card] {
        let pool = cards.filter { card in
            guard !seen.contains(card.masterCardId) else { return false }
            return !card.displayImageSrc.isEmpty
        }

        // Priority pass — for each rarity fragment, pick the first match.
        var ordered: [Card] = []
        var picked: Set<String> = []
        for fragment in priorityRarityFragments {
            if let match = pool.first(where: { ($0.rarity ?? "").localizedCaseInsensitiveContains(fragment) && !picked.contains($0.masterCardId) }) {
                ordered.append(match)
                picked.insert(match.masterCardId)
            }
        }

        // Backfill from anything in the pool we haven't already picked.
        for card in pool where !picked.contains(card.masterCardId) {
            ordered.append(card)
            picked.insert(card.masterCardId)
        }

        return ordered
    }
}
