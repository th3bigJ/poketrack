import Foundation
import Observation

@Observable
@MainActor
final class CardDataService {
    private(set) var sets: [TCGSet] = []
    /// From R2 `pokemon.json` (see `nationalDexNumber`); sorted ascending when loaded.
    private(set) var nationalDexPokemon: [NationalDexPokemon] = []
    private(set) var cardsBySet: [String: [Card]] = [:]
    private(set) var lastError: String?
    private(set) var isLoading = false
    private(set) var isSearchIndexReady = false

    private let session: URLSession
    private let fileManager: FileManager
    private let searchIndex = CardSearchIndex()

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    private var documentsCardsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("cards", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func loadSets() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        let base = AppConfiguration.r2BaseURL
        guard base.host != "invalid.local" else {
            lastError = "Set POKETRACK_R2_BASE_URL in Info.plist to your CDN root."
            return
        }

        let url = AppConfiguration.r2CatalogURL(path: "sets.json")

        // Always prefer live `sets.json` when online so metadata like `logoSrc` matches R2. Previously we
        // returned SQLite first and never refreshed set rows from the network, so stale/empty `logoSrc`
        // could persist while card images (from other JSON) still loaded correctly.
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode([TCGSet].self, from: data)
            sets = decoded.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
            Task { await self.prepareSearchIndex() }
            return
        } catch {
            lastError = error.localizedDescription
        }

        do {
            try CatalogStore.shared.open()
            let fromDb = try CatalogStore.shared.fetchAllSets()
            if !fromDb.isEmpty {
                sets = fromDb.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
                lastError = nil
                Task { await self.prepareSearchIndex() }
                return
            }
        } catch {
            // Keep lastError from network attempt when offline / DB missing.
        }

        if sets.isEmpty {
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

    private func prepareSearchIndex() async {
        await searchIndex.prepare(sets: sets) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode)
        }
        isSearchIndexReady = searchIndex.isReady
    }

    func loadCards(forSetCode setCode: String) async -> [Card] {
        if let cached = cardsBySet[setCode] { return cached }

        if let fromDb = try? await loadCardsFromDatabase(setCode: setCode), !fromDb.isEmpty {
            cardsBySet[setCode] = fromDb
            return fromDb
        }

        if let bundled = loadBundledCards(setCode: setCode) {
            cardsBySet[setCode] = bundled
            return bundled
        }

        if let disk = loadDocumentsCards(setCode: setCode) {
            cardsBySet[setCode] = disk
            return disk
        }

        let base = AppConfiguration.r2BaseURL
        guard base.host != "invalid.local" else { return [] }

        let url = AppConfiguration.r2CatalogURL(path: "cards/\(setCode).json")
        do {
            let (data, _) = try await session.data(from: url)
            let cards = try JSONDecoder().decode([Card].self, from: data)
            cardsBySet[setCode] = cards
            saveDocumentsCards(setCode: setCode, data: data)
            return cards
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func loadAllCards() async -> [Card] {
        do {
            try CatalogStore.shared.open()
            let cards = try CatalogStore.shared.fetchAllCards()
            if !cards.isEmpty {
                return cards
            }
        } catch {
            // Fall through to in-memory / network-backed set loads.
        }

        guard !sets.isEmpty else { return [] }
        var out: [Card] = []
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            out.append(contentsOf: cards)
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
            let refs = try CatalogStore.shared.fetchAllCardRefs()
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

    /// All cards in the catalog that include a dex id (for species detail).
    func cards(matchingNationalDex dexId: Int) async -> [Card] {
        var out: [Card] = []
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            out.append(contentsOf: cards.filter { $0.dexIds?.contains(dexId) == true })
        }
        return sortCardsByReleaseDateNewestFirst(out)
    }

    func search(query: String) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        await searchIndex.prepare(sets: sets) { [weak self] setCode in
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

        await searchIndex.prepare(sets: sets) { [weak self] setCode in
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
        var bySet: [String: Set<String>] = [:]
        for row in ranked {
            bySet[row.ref.setCode, default: []].insert(row.ref.masterCardId)
        }
        var cardByKey: [String: Card] = [:]
        for (setCode, ids) in bySet {
            let loaded = await loadCards(forSetCode: setCode)
            for c in loaded where ids.contains(c.masterCardId) {
                cardByKey["\(c.setCode)|\(c.masterCardId)"] = c
            }
        }
        return ranked.compactMap { cardByKey["\($0.ref.setCode)|\($0.ref.masterCardId)"] }
    }

    private func cards(for refs: Set<CardRef>) async -> [Card] {
        var bySet: [String: Set<String>] = [:]
        for ref in refs {
            bySet[ref.setCode, default: []].insert(ref.masterCardId)
        }
        var out: [Card] = []
        for (setCode, ids) in bySet {
            let loaded = await loadCards(forSetCode: setCode)
            out.append(contentsOf: loaded.filter { ids.contains($0.masterCardId) })
        }
        return sortCardsByReleaseDateNewestFirst(out)
    }

    /// Search by card name only — never matches on attacks, rules, HP, or set code.
    /// Used by the scanner so attack/rules text can't pull in wrong-name cards.
    func searchByName(query: String) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        await searchIndex.prepare(sets: sets) { [weak self] setCode in
            guard let self else { return [] }
            return await self.loadCards(forSetCode: setCode)
        }
        isSearchIndexReady = searchIndex.isReady

        return await linearNameSearch(normalizedQuery: q)
    }

    private func linearNameSearch(normalizedQuery q: String) async -> [Card] {
        // Fuzzy: every token in the query must appear in the card name.
        let tokens = q.split(whereSeparator: \.isWhitespace).map(String.init)
        var results: [Card] = []
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
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
        var results: [Card] = []
        for set in sets {
            let code = set.setCode
            let cards = await loadCards(forSetCode: code)
            for card in cards {
                let blob = card.searchIndexBlob.lowercased()
                if blob.contains(q) {
                    results.append(card)
                }
            }
        }
        return sortCardsByReleaseDateNewestFirst(results)
    }

    private func loadCardsFromDatabase(setCode: String) async throws -> [Card] {
        try CatalogStore.shared.open()
        return try CatalogStore.shared.fetchCards(setCode: setCode)
    }

    /// Resolves one card by `masterCardId` (same string as wishlist `cardID`). SQLite first, then scans loaded sets if needed.
    func loadCard(masterCardId: String) async -> Card? {
        do {
            try CatalogStore.shared.open()
            if let c = try CatalogStore.shared.fetchCard(masterCardId: masterCardId) {
                return c
            }
        } catch {
            // Fall through to linear scan.
        }
        for set in sets {
            let cards = await loadCards(forSetCode: set.setCode)
            if let c = cards.first(where: { $0.masterCardId == masterCardId }) {
                return c
            }
        }
        return nil
    }

    private func loadBundledCards(setCode: String) -> [Card]? {
        guard let url = Bundle.main.url(forResource: setCode, withExtension: "json") else { return nil }
        return try? loadCardsFile(url: url)
    }

    private func loadDocumentsCards(setCode: String) -> [Card]? {
        let url = documentsCardsDirectory.appendingPathComponent("\(setCode).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? loadCardsFile(url: url)
    }

    private func loadCardsFile(url: URL) throws -> [Card] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Card].self, from: data)
    }

    private func saveDocumentsCards(setCode: String, data: Data) {
        let url = documentsCardsDirectory.appendingPathComponent("\(setCode).json")
        try? data.write(to: url, options: .atomic)
    }
}
