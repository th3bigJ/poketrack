import CryptoKit
import Foundation

struct CardRef: Hashable, Codable {
    var masterCardId: String
    var setCode: String
}

/// Splits card text into lowercase alphanumeric tokens for inverted-index search.
enum SearchTokenizer {
    static func tokens(from text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

private struct PersistedSearchIndex: Codable {
    var signature: String
    /// Token → list of [masterCardId, setCode] pairs.
    var inverted: [String: [[String]]]
}

/// Disk-backed inverted word index over catalog cards (rebuilt when the set list signature changes).
final class CardSearchIndex {
    private(set) var isReady = false
    private var inverted: [String: Set<CardRef>] = [:]
    private var loadedSignature: String = ""

    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("search_index", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("inverted.json")
    }

    static func versionSignature(for sets: [TCGSet]) -> String {
        let codes = sets.map(\.setCode).sorted().joined(separator: "|")
        let digest = SHA256.hash(data: Data(codes.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func loadFromDiskIfPresent() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let payload = try? JSONDecoder().decode(PersistedSearchIndex.self, from: data) else { return }
        loadedSignature = payload.signature
        var map: [String: Set<CardRef>] = [:]
        for (token, rows) in payload.inverted {
            map[token] = Set(rows.map { CardRef(masterCardId: $0[0], setCode: $0[1]) })
        }
        inverted = map
        isReady = !inverted.isEmpty
    }

    /// Loads cache from disk, then rebuilds if the catalog signature changed or the cache is missing.
    func prepare(
        sets: [TCGSet],
        loadCards: @escaping (String) async -> [Card]
    ) async {
        loadFromDiskIfPresent()
        let sig = Self.versionSignature(for: sets)
        if loadedSignature == sig, !inverted.isEmpty {
            isReady = true
            return
        }
        await rebuild(versionSignature: sig, sets: sets, loadCards: loadCards)
    }

    /// Token intersection over the inverted index. Empty set means no posting-list hits (caller may fall back to linear scan).
    func refs(matchingNormalizedQuery query: String) -> Set<CardRef> {
        guard !inverted.isEmpty else { return [] }
        let tokens = SearchTokenizer.tokens(from: query)
        guard !tokens.isEmpty else { return [] }

        var intersection: Set<CardRef>?
        for t in tokens {
            let bucket = inverted[t] ?? []
            if let existing = intersection {
                intersection = existing.intersection(bucket)
            } else {
                intersection = bucket
            }
        }
        return intersection ?? []
    }

    private func rebuild(
        versionSignature: String,
        sets: [TCGSet],
        loadCards: (String) async -> [Card]
    ) async {
        inverted = [:]
        for set in sets {
            if Task.isCancelled { return }
            let cards = await loadCards(set.setCode)
            for card in cards {
                let blob = "\(card.cardName) \(card.cardNumber) \(card.fullDisplayName ?? "") \(card.setCode)"
                let tokens = SearchTokenizer.tokens(from: blob)
                let ref = CardRef(masterCardId: card.masterCardId, setCode: card.setCode)
                for t in tokens {
                    inverted[t, default: []].insert(ref)
                }
            }
        }
        loadedSignature = versionSignature
        isReady = !inverted.isEmpty
        saveToDisk()
    }

    private func saveToDisk() {
        var encodable: [String: [[String]]] = [:]
        for (token, refs) in inverted {
            encodable[token] = refs.map { [ $0.masterCardId, $0.setCode ] }
        }
        let payload = PersistedSearchIndex(signature: loadedSignature, inverted: encodable)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
