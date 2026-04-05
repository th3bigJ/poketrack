import Foundation
import Observation

@Observable
final class CardDataService {
    private(set) var sets: [TCGSet] = []
    private(set) var cardsBySet: [String: [Card]] = [:]
    private(set) var lastError: String?
    private(set) var isLoading = false

    private let session: URLSession
    private let fileManager: FileManager

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
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode([TCGSet].self, from: data)
            sets = decoded.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        } catch {
            lastError = error.localizedDescription
            sets = []
        }
    }

    func loadCards(forSetCode setCode: String) async -> [Card] {
        if let cached = cardsBySet[setCode] { return cached }

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

    func card(masterCardId: String, setCode: String) -> Card? {
        cardsBySet[setCode]?.first { $0.masterCardId == masterCardId }
    }

    func search(query: String) async -> [Card] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var results: [Card] = []
        for set in sets {
            let code = set.setCode
            let cards = await loadCards(forSetCode: code)
            for card in cards {
                if card.cardName.lowercased().contains(q)
                    || card.cardNumber.lowercased().contains(q)
                    || card.fullDisplayName?.lowercased().contains(q) == true {
                    results.append(card)
                }
            }
        }
        return results
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
