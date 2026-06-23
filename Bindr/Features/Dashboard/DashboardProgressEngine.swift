import Foundation

struct DashboardProgressSnapshot: Equatable, Identifiable, Sendable {
    let targetID: UUID
    let title: String
    let modeLabel: String
    let collected: Int
    let total: Int
    let artworkURL: URL?

    var id: UUID { targetID }

    var progress: CGFloat {
        guard total > 0 else { return 0 }
        return min(CGFloat(collected) / CGFloat(total), 1)
    }
}

@MainActor
enum DashboardProgressEngine {
    static func snapshots(
        for targets: [DashboardProgressTarget],
        collectionItems: [CollectionItem],
        services: AppServices
    ) async -> [DashboardProgressSnapshot] {
        guard !targets.isEmpty else { return [] }

        let brand = services.brandSettings.selectedCatalogBrand
        let ownedVariants = ownedVariantsByCardID(
            from: collectionItems,
            brand: brand,
            variantsCatalog: services.variantsCatalog
        )

        var results: [DashboardProgressSnapshot] = []
        results.reserveCapacity(targets.count)

        for target in targets {
            if let snapshot = await snapshot(
                for: target,
                ownedVariants: ownedVariants,
                services: services
            ) {
                results.append(snapshot)
            }
        }
        return results
    }

    private static func snapshot(
        for target: DashboardProgressTarget,
        ownedVariants: [String: Set<String>],
        services: AppServices
    ) async -> DashboardProgressSnapshot? {
        switch target.kind {
        case .set:
            guard let setCode = target.setCode?.lowercased(),
                  let set = services.cardData.sets.first(where: { $0.setCode.lowercased() == setCode })
            else { return nil }

            let cards = await services.cardData.loadCards(forSetCode: set.setCode)
            let counts = await setProgressCounts(
                set: set,
                cards: cards,
                mode: target.completionMode,
                ownedVariants: ownedVariants,
                services: services
            )
            let logoCandidates = AppConfiguration.setLogoURLCandidates(
                logoSrc: set.logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            return DashboardProgressSnapshot(
                targetID: target.id,
                title: target.displayTitle,
                modeLabel: target.completionMode.chipLabel,
                collected: counts.collected,
                total: counts.total,
                artworkURL: logoCandidates.first
            )

        case .pokemon:
            guard let dexId = target.dexId else { return nil }
            let cards = await services.cardData.cards(matchingNationalDex: dexId)
            guard !cards.isEmpty else { return nil }

            let counts = await dexProgressCounts(
                cards: cards,
                mode: target.completionMode,
                ownedVariants: ownedVariants,
                services: services
            )
            let pokemon = services.cardData.nationalDexPokemon.first { $0.nationalDexNumber == dexId }
            let artworkURL = pokemon.map {
                AppConfiguration.pokemonArtURL(imageFileName: $0.imageUrl)
            } ?? nil

            return DashboardProgressSnapshot(
                targetID: target.id,
                title: target.displayTitle,
                modeLabel: target.completionMode.chipLabel,
                collected: counts.collected,
                total: counts.total,
                artworkURL: artworkURL
            )
        }
    }

    private static func ownedVariantsByCardID(
        from collectionItems: [CollectionItem],
        brand: TCGBrand,
        variantsCatalog: VariantsCatalogService
    ) -> [String: Set<String>] {
        var ownedVariantsByCardID: [String: Set<String>] = [:]
        for item in collectionItems where item.quantity > 0 {
            guard TCGBrand.inferredFromMasterCardId(item.cardID) == brand else { continue }
            let variant = item.variantKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalized = variant.isEmpty ? "normal" : variant
            guard !variantsCatalog.isChampionshipVariant(normalized) else { continue }
            ownedVariantsByCardID[item.cardID, default: []].insert(normalized)
        }
        return ownedVariantsByCardID
    }

    private static func setProgressCounts(
        set: TCGSet,
        cards: [Card],
        mode: SetCompletionMode,
        ownedVariants: [String: Set<String>],
        services: AppServices
    ) async -> (collected: Int, total: Int) {
        switch mode {
        case .full:
            let collected = cards.filter { ownedVariants[$0.masterCardId] != nil }.count
            return (collected, set.cardCountTotal ?? cards.count)

        case .master, .grandMaster:
            let total = await services.variantsCatalog.variantSlotCount(
                forSetCode: set.setCode,
                mode: mode,
                cardData: services.cardData,
                pricing: services.pricing
            )
            let fallbackTotal = total > 0 ? total : (set.masterSetTotal ?? set.cardCountTotal ?? cards.count)
            let collected = cards.reduce(0) { partial, card in
                let owned = ownedVariants[card.masterCardId] ?? []
                let counted = owned.filter { services.variantsCatalog.includesVariant($0, mode: mode) }.count
                return partial + counted
            }
            return (collected, fallbackTotal)
        }
    }

    private static func dexProgressCounts(
        cards: [Card],
        mode: SetCompletionMode,
        ownedVariants: [String: Set<String>],
        services: AppServices
    ) async -> (collected: Int, total: Int) {
        let ownedCardIDs = Set(ownedVariants.keys)

        switch mode {
        case .full:
            let collected = cards.filter { ownedCardIDs.contains($0.masterCardId) }.count
            return (collected, cards.count)

        case .master, .grandMaster:
            var variantRows = 0
            var collected = 0
            for card in cards {
                let keys = await services.pricing.variantKeys(for: card)
                let eligible = services.variantsCatalog.eligibleVariantKeys(
                    from: keys,
                    card: card,
                    mode: mode
                )
                variantRows += eligible.count
                let owned = ownedVariants[card.masterCardId] ?? []
                collected += owned.filter { services.variantsCatalog.includesVariant($0, mode: mode) }.count
            }
            let total = variantRows > 0 ? variantRows : cards.count
            return (collected, total)
        }
    }
}
