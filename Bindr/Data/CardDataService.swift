import Foundation
import Observation

@Observable
@MainActor
final class CardDataService {
    private(set) var sets: [TCGSet] = []
    /// From R2 `pokemon.json` (see `nationalDexNumber`); sorted ascending when loaded.
    private(set) var nationalDexPokemon: [NationalDexPokemon] = []
    /// From R2 `onepiece/character-names.json`; sorted alphabetically when loaded.
    private(set) var onePieceCharacterNames: [String] = []
    /// From R2 `onepiece/character-subtypes.json`; sorted alphabetically when loaded.
    private(set) var onePieceCharacterSubtypes: [String] = []
    private(set) var cardsBySet: [String: [Card]] = [:]
    private(set) var lastError: String?
    private(set) var isLoading = false
    private(set) var isSearchIndexReady = false

    private let session: URLSession
    private let fileManager: FileManager
    private let searchIndex = CardSearchIndex()
    private let brandSettings: BrandSettings

    init(
        brandSettings: BrandSettings,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.brandSettings = brandSettings
        self.session = session
        self.fileManager = fileManager
    }

    /// Call after the user switches the browse brand (carousel or account). Clears caches and reloads `sets` + search index.
    func reloadAfterBrandChange() async {
        cardsBySet = [:]
        browseFeedSessionRefs = nil
        isSearchIndexReady = false
        await loadSets(preferSyncedCatalog: false)
    }

    /// Clears only the shuffled browse feed session (e.g. right after a catalog sync that already ran ``loadSets``). Avoids duplicate SQLite + search index work on tab entry.
    func resetBrowseFeedSessionOnly() {
        browseFeedSessionRefs = nil
    }

    /// Loads the browse set list from the local SQLite catalog only (populated by ``CatalogSyncCoordinator``).
    func loadSets(preferSyncedCatalog: Bool = false) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            try CatalogStore.shared.open()
            let brand = brandSettings.selectedCatalogBrand
            let rows = try CatalogStore.shared.fetchAllSets(for: brand)
            guard !rows.isEmpty else {
                lastError = "No \(brand.displayTitle) catalog on this device. Turn the game on under Card catalog and download while online."
                sets = []
                return
            }
            sets = rows.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            lastError = nil
            Task { await self.prepareSearchIndex() }
        } catch {
            lastError = error.localizedDescription
            sets = []
        }
    }

    /// Loads `pokemon.json` next to `sets.json` under the catalog prefix. Falls back to bundled `pokemon.json` for previews/offline.
    func loadNationalDexPokemon() async {
        let base = AppConfiguration.r2BaseURL
        if base.host != "invalid.local" {
            let url = AppConfiguration.r2CatalogURL(path: "pokemon.json")
            do {
                let (data, _) = try await session.data(from: url)
                let decoded = try JSONDecoder().decode([NationalDexPokemon].self, from: data)
                nationalDexPokemon = decoded.sorted { $0.nationalDexNumber < $1.nationalDexNumber }
                return
            } catch {
                // Fall through to bundle.
            }
        }
        if let url = Bundle.main.url(forResource: "pokemon", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([NationalDexPokemon].self, from: data) {
            nationalDexPokemon = decoded.sorted { $0.nationalDexNumber < $1.nationalDexNumber }
        } else {
            nationalDexPokemon = []
        }
    }

    /// Pokémon rows for browsing (R2 list), already sorted by `nationalDexNumber`.
    func nationalDexPokemonSorted() -> [NationalDexPokemon] {
        nationalDexPokemon.sorted { $0.nationalDexNumber < $1.nationalDexNumber }
    }

    /// Clears Pokédex rows when the user disables the Pokémon brand (saves memory; reloaded on next `loadNationalDexPokemon()`).
    func clearNationalDexForDisabledPokemon() {
        nationalDexPokemon = []
    }

    func clearOnePieceBrowseMetadata() {
        onePieceCharacterNames = []
        onePieceCharacterSubtypes = []
    }

    /// Loads ONE PIECE browse metadata lists from R2 and keeps them alphabetized for list UIs.
    func loadOnePieceBrowseMetadata() async {
        do {
            try CatalogStore.shared.open()
            let names = decodeStoredStringList(forMetaKey: "onepiece_character_names_json")
            let subtypes = decodeStoredStringList(forMetaKey: "onepiece_character_subtypes_json")
            onePieceCharacterNames = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            onePieceCharacterSubtypes = subtypes.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            onePieceCharacterNames = []
            onePieceCharacterSubtypes = []
        }
    }

    private func decodeStoredStringList(forMetaKey key: String) -> [String] {
        guard let data = CatalogStore.shared.metaData(key),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func prepareSearchIndex() async {
        await searchIndex.prepare(sets: sets, brand: brandSettings.selectedCatalogBrand) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode)
        }
        isSearchIndexReady = searchIndex.isReady
    }

    func loadCards(forSetCode setCode: String) async -> [Card] {
        if let cached = cardsBySet[setCode] { return cached }
        let brand = brandSettings.selectedCatalogBrand
        if let fromDb = try? await loadCardsFromDatabase(setCode: setCode, brand: brand), !fromDb.isEmpty {
            cardsBySet[setCode] = fromDb
            return fromDb
        }
        return []
    }

    func loadAllCards() async -> [Card] {
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllCards(for: brandSettings.selectedCatalogBrand)
            if !cards.isEmpty {
                return cards
            }
        } catch {
            // Fall through.
        }

        guard !sets.isEmpty else { return [] }
        var out: [Card] = []
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            out.append(contentsOf: cards)
        }
        return out
    }

    func loadAllBrowseFilterCards() async -> [BrowseFilterCard] {
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllBrowseFilterCards(for: brandSettings.selectedCatalogBrand)
            if !cards.isEmpty {
                return cards
            }
        } catch {
            // Fall through.
        }

        guard !sets.isEmpty else { return [] }
        var out: [BrowseFilterCard] = []
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            out.reserveCapacity(out.count + cards.count)
            out.append(contentsOf: cards.map { card in
                BrowseFilterCard(
                    masterCardId: card.masterCardId,
                    setCode: card.setCode,
                    cardNumber: card.cardNumber,
                    cardName: card.cardName,
                    rarity: card.rarity,
                    category: card.category,
                    elementTypes: card.elementTypes,
                    trainerType: card.trainerType,
                    energyType: card.energyType,
                    regulationMark: card.regulationMark,
                    artist: card.artist,
                    subtype: card.subtype,
                    subtypes: card.subtypes,
                    weakness: card.weakness,
                    resistance: card.resistance,
                    pricingVariants: card.pricingVariants,
                    opAttributes: card.opAttributes,
                    opCost: card.opCost,
                    opCounter: card.opCounter,
                    opLife: card.opLife,
                    opPower: card.hp
                )
            })
        }
        return out
    }

    /// Substring match on set name, code, or series (for universal search).
    func searchSets(matching query: String) -> [TCGSet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return sets.filter { set in
            set.name.lowercased().contains(q)
                || set.setCode.lowercased().contains(q)
                || (set.seriesName?.lowercased().contains(q) == true)
        }
    }

    /// All sets sorted by `releaseDate` descending (newest first). String compare on ISO-ish dates from catalog.
    func allSetsSortedByReleaseDateNewestFirst() -> [TCGSet] {
        sets.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
    }

    /// Lookup for ordering cards: `setCode` → `releaseDate` string (ISO-ish; same compare as `sets` ordering).
    private var releaseDateBySetCode: [String: String] {
        Dictionary(uniqueKeysWithValues: sets.map { ($0.setCode, $0.releaseDate ?? "") })
    }

    /// Newest-released sets first; within one set, `cardNumber` ascending (catalog order).
    private func sortCardsByReleaseDateNewestFirst(_ cards: [Card]) -> [Card] {
        guard !cards.isEmpty else { return cards }
        let dates = releaseDateBySetCode
        return cards.sorted { a, b in
            let da = dates[a.setCode] ?? ""
            let db = dates[b.setCode] ?? ""
            if da != db {
                return da > db
            }
            if a.setCode != b.setCode {
                return a.setCode.localizedStandardCompare(b.setCode) == .orderedAscending
            }
            return a.cardNumber.localizedStandardCompare(b.cardNumber) == .orderedAscending
        }
    }

    /// Stable shuffle order for the Browse tab for this app session. New shuffle only when `forceReshuffle` is true (pull-to-refresh) or before first load.
    private var browseFeedSessionRefs: [CardRef]?

    /// Card order for the Browse grid. Set `forceReshuffle` to `true` on pull-to-refresh; otherwise the same order is reused until the app restarts.
    func browseFeedCardRefs(forceReshuffle: Bool) async -> [CardRef] {
        if forceReshuffle {
            browseFeedSessionRefs = nil
        }
        if let cached = browseFeedSessionRefs {
            return cached
        }
        let refs = await buildShuffledBrowseCardRefs()
        browseFeedSessionRefs = refs
        return refs
    }

    private func buildShuffledBrowseCardRefs() async -> [CardRef] {
        do {
            try CatalogStore.shared.open()
            let refs = try CatalogStore.shared.fetchAllCardRefs(for: brandSettings.selectedCatalogBrand)
            if !refs.isEmpty {
                return refs.shuffled()
            }
        } catch {
            // Fall through.
        }
        guard !sets.isEmpty else { return [] }
        var all: [CardRef] = []
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            all.reserveCapacity(all.count + cards.count)
            for c in cards {
                all.append(CardRef(masterCardId: c.masterCardId, setCode: c.setCode))
            }
        }
        return all.shuffled()
    }

    /// Resolves `refs` to full `Card` models in **the same order** as `refs` (for paginated grids).
    func cardsInOrder(refs: [CardRef]) async -> [Card] {
        guard !refs.isEmpty else { return [] }
        var bySet: [String: Set<String>] = [:]
        for ref in refs {
            bySet[ref.setCode, default: []].insert(ref.masterCardId)
        }
        var cardByKey: [String: Card] = [:]
        for (setCode, ids) in bySet {
            let loaded = await loadCards(forSetCode: setCode)
            for c in loaded where ids.contains(c.masterCardId) {
                cardByKey["\(c.setCode)|\(c.masterCardId)"] = c
            }
        }
        return refs.compactMap { cardByKey["\($0.setCode)|\($0.masterCardId)"] }
    }

    /// Substring match on Pokédex rows (`pokemon.json`): kebab-case `name`, display title, or dex number string.
    func searchPokemon(matching query: String) -> [NationalDexPokemon] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return nationalDexPokemon.filter { row in
            row.name.lowercased().contains(q)
                || row.displayName.lowercased().contains(q)
                || String(row.nationalDexNumber).contains(q)
        }
    }

    func searchOnePieceCharacterNames(matching query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return onePieceCharacterNames.filter { $0.lowercased().contains(q) }
    }

    func searchOnePieceCharacterSubtypes(matching query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return onePieceCharacterSubtypes.filter { $0.lowercased().contains(q) }
    }

    /// All cards in the catalog that include a dex id (for species detail).
    func cards(matchingNationalDex dexId: Int) async -> [Card] {
        var out: [Card] = []
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            out.append(contentsOf: cards.filter { $0.dexIds?.contains(dexId) == true })
        }
        return sortCardsByReleaseDateNewestFirst(out)
    }

    /// ONE PIECE cards whose printed card name matches a browse character entry exactly (case-insensitive).
    func cards(matchingOnePieceCharacterName name: String) async -> [Card] {
        let q = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let normalized = q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let all = await allCards(for: .onePiece)
        let matches = all.filter {
            $0.cardName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalized
        }
        return sortCardsByReleaseDateNewestFirst(matches)
    }

    /// ONE PIECE cards whose subtype list contains the selected browse subtype exactly (case-insensitive).
    func cards(matchingOnePieceSubtype subtype: String) async -> [Card] {
        let q = subtype.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let normalized = q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let all = await allCards(for: .onePiece)
        let matches = all.filter { card in
            let values = (card.subtypes ?? []) + [card.subtype].compactMap { $0 }
            return values.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) == normalized
            }
        }
        return sortCardsByReleaseDateNewestFirst(matches)
    }

    func search(query: String) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        await searchIndex.prepare(sets: sets, brand: brandSettings.selectedCatalogBrand) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode)
        }
        isSearchIndexReady = searchIndex.isReady

        if searchIndex.isReady {
            let refs = searchIndex.refs(matchingNormalizedQuery: q)
            if !refs.isEmpty {
                return await cards(for: refs)
            }
        }
        return await linearSubstringSearch(normalizedQuery: q)
    }

    /// Partial token overlap (not strict intersection). Best for long **trainer rules** text when OCR only matches part of the catalog `rules` field.
    func searchSoftTokenMatch(query: String) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        await searchIndex.prepare(sets: sets, brand: brandSettings.selectedCatalogBrand) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode)
        }
        isSearchIndexReady = searchIndex.isReady

        guard searchIndex.isReady else {
            return await linearSubstringSearch(normalizedQuery: q)
        }

        let ranked = searchIndex.softMatchRefs(normalizedQuery: q)
        guard !ranked.isEmpty else { return [] }
        return await cardsPreservingSoftMatchOrder(ranked)
    }

    private func cardsPreservingSoftMatchOrder(_ ranked: [(ref: CardRef, tokenHits: Int)]) async -> [Card] {
        await cardsPreservingSoftMatchOrder(ranked, catalogBrand: brandSettings.selectedCatalogBrand)
    }

    private func cards(for refs: Set<CardRef>) async -> [Card] {
        await cards(for: refs, catalogBrand: brandSettings.selectedCatalogBrand)
    }

    /// Search by card name only — never matches on attacks, rules, HP, or set code.
    /// Used by the scanner so attack/rules text can't pull in wrong-name cards.
    func searchByName(query: String) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        await searchIndex.prepare(sets: sets, brand: brandSettings.selectedCatalogBrand) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode)
        }
        isSearchIndexReady = searchIndex.isReady

        return await linearNameSearch(normalizedQuery: q)
    }

    private func linearNameSearch(normalizedQuery q: String) async -> [Card] {
        await linearNameSearch(normalizedQuery: q, sets: sets, catalogBrand: brandSettings.selectedCatalogBrand)
    }

    private func linearNameSearch(normalizedQuery q: String, sets brandSets: [TCGSet], catalogBrand: TCGBrand) async -> [Card] {
        let tokens = q.split(whereSeparator: \.isWhitespace).map(String.init)
        var results: [Card] = []
        for set in brandSets {
            let cards = await loadCards(forSetCode: set.setCode, catalogBrand: catalogBrand)
            for card in cards {
                let name = card.cardName.lowercased()
                if tokens.allSatisfy({ name.contains($0) }) {
                    results.append(card)
                }
            }
        }
        return sortCardsByReleaseDateNewestFirst(results)
    }

    private func linearSubstringSearch(normalizedQuery q: String) async -> [Card] {
        await linearSubstringSearch(normalizedQuery: q, sets: sets, catalogBrand: brandSettings.selectedCatalogBrand)
    }

    private func linearSubstringSearch(normalizedQuery q: String, sets brandSets: [TCGSet], catalogBrand: TCGBrand) async -> [Card] {
        var results: [Card] = []
        for set in brandSets {
            let code = set.setCode
            let cards = await loadCards(forSetCode: code, catalogBrand: catalogBrand)
            for card in cards {
                let blob = card.searchIndexBlob.lowercased()
                if blob.contains(q) {
                    results.append(card)
                }
            }
        }
        return sortCardsByReleaseDateNewestFirst(results)
    }

    // MARK: - Scanner (search without changing browse `selectedCatalogBrand`)

    /// Loads set list for a brand without mutating browse state.
    func catalogSets(for brand: TCGBrand) async -> [TCGSet] {
        do {
            try CatalogStore.shared.open()
            let rows = try CatalogStore.shared.fetchAllSets(for: brand)
            return rows.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        } catch {
            return []
        }
    }

    /// All ONE PIECE cards sharing the same normalized collector id (e.g. every variant with printed `ST29-004`).
    func allOnePieceCardsMatchingNormalizedCollectorID(_ normalized: String) async -> [Card] {
        let key = CardOCRFieldExtractor.normalizedOnePieceCollectorID(normalized)
        guard !key.isEmpty else { return [] }
        do {
            try CatalogStore.shared.open()
            let all = try CatalogStore.shared.fetchAllCards(for: .onePiece)
            return all.filter { CardOCRFieldExtractor.normalizedOnePieceCollectorID($0.cardNumber) == key }
        } catch {
            return []
        }
    }

    private var cardsForCatalogBrandCache: [String: [Card]] = [:]

    /// Loads cards for `setCode` using the given franchise (not necessarily the current browse brand).
    func loadCards(forSetCode setCode: String, catalogBrand: TCGBrand) async -> [Card] {
        let cacheKey = "\(catalogBrand.rawValue)|\(setCode)"
        if catalogBrand == brandSettings.selectedCatalogBrand, let hit = cardsBySet[setCode] {
            return hit
        }
        if let hit = cardsForCatalogBrandCache[cacheKey] { return hit }

        let cards: [Card]
        if let fromDb = try? await loadCardsFromDatabase(setCode: setCode, brand: catalogBrand), !fromDb.isEmpty {
            cards = fromDb
        } else {
            cards = []
        }
        cardsForCatalogBrandCache[cacheKey] = cards
        return cards
    }

    func searchByName(query: String, catalogBrand: TCGBrand) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let brandSets = await catalogSets(for: catalogBrand)
        await searchIndex.prepare(sets: brandSets, brand: catalogBrand) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode, catalogBrand: catalogBrand)
        }
        isSearchIndexReady = searchIndex.isReady
        return await linearNameSearch(normalizedQuery: q, sets: brandSets, catalogBrand: catalogBrand)
    }

    func search(query: String, catalogBrand: TCGBrand) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let brandSets = await catalogSets(for: catalogBrand)
        await searchIndex.prepare(sets: brandSets, brand: catalogBrand) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode, catalogBrand: catalogBrand)
        }
        isSearchIndexReady = searchIndex.isReady
        if searchIndex.isReady {
            let refs = searchIndex.refs(matchingNormalizedQuery: q)
            if !refs.isEmpty {
                return await cards(for: refs, catalogBrand: catalogBrand)
            }
        }
        return await linearSubstringSearch(normalizedQuery: q, sets: brandSets, catalogBrand: catalogBrand)
    }

    func searchSoftTokenMatch(query: String, catalogBrand: TCGBrand) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let brandSets = await catalogSets(for: catalogBrand)
        await searchIndex.prepare(sets: brandSets, brand: catalogBrand) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode, catalogBrand: catalogBrand)
        }
        isSearchIndexReady = searchIndex.isReady
        guard searchIndex.isReady else {
            return await linearSubstringSearch(normalizedQuery: q, sets: brandSets, catalogBrand: catalogBrand)
        }
        let ranked = searchIndex.softMatchRefs(normalizedQuery: q)
        guard !ranked.isEmpty else { return [] }
        return await cardsPreservingSoftMatchOrder(ranked, catalogBrand: catalogBrand)
    }

    private func cards(for refs: Set<CardRef>, catalogBrand: TCGBrand) async -> [Card] {
        var bySet: [String: Set<String>] = [:]
        for ref in refs {
            bySet[ref.setCode, default: []].insert(ref.masterCardId)
        }
        var out: [Card] = []
        for (setCode, ids) in bySet {
            let loaded = await loadCards(forSetCode: setCode, catalogBrand: catalogBrand)
            out.append(contentsOf: loaded.filter { ids.contains($0.masterCardId) })
        }
        return sortCardsByReleaseDateNewestFirst(out)
    }

    private func cardsPreservingSoftMatchOrder(_ ranked: [(ref: CardRef, tokenHits: Int)], catalogBrand: TCGBrand) async -> [Card] {
        var bySet: [String: Set<String>] = [:]
        for row in ranked {
            bySet[row.ref.setCode, default: []].insert(row.ref.masterCardId)
        }
        var cardByKey: [String: Card] = [:]
        for (setCode, ids) in bySet {
            let loaded = await loadCards(forSetCode: setCode, catalogBrand: catalogBrand)
            for c in loaded where ids.contains(c.masterCardId) {
                cardByKey["\(c.setCode)|\(c.masterCardId)"] = c
            }
        }
        return ranked.compactMap { cardByKey["\($0.ref.setCode)|\($0.ref.masterCardId)"] }
    }

    private func loadCardsFromDatabase(setCode: String, brand: TCGBrand) async throws -> [Card] {
        try CatalogStore.shared.open()
        return try CatalogStore.shared.fetchCards(setCode: setCode, brand: brand)
    }

    private func allCards(for brand: TCGBrand) async -> [Card] {
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllCards(for: brand)
            if !cards.isEmpty {
                return cards
            }
        } catch {
            // Fall through.
        }

        let brandSets = await catalogSets(for: brand)
        var out: [Card] = []
        for set in brandSets {
            out.append(contentsOf: await loadCards(forSetCode: set.setCode, catalogBrand: brand))
        }
        return out
    }

    /// Resolves one card by `masterCardId` from SQLite (franchise inferred from the id shape).
    func loadCard(masterCardId: String) async -> Card? {
        let inferred = TCGBrand.inferredFromMasterCardId(masterCardId)
        do {
            try CatalogStore.shared.open()
            if let c = try CatalogStore.shared.fetchCard(masterCardId: masterCardId, brand: inferred) {
                return c
            }
        } catch {
            // Fall through.
        }
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            if let c = cards.first(where: { $0.masterCardId == masterCardId }) {
                return c
            }
        }
        return nil
    }
}
