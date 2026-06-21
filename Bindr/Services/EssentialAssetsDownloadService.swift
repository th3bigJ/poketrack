import Foundation
import Observation

/// Downloads set logos, set symbols, Pokémon art, and sealed product images on first launch
/// (and after any catalog sync) for every enabled brand — regardless of whether offline image
/// packs are toggled on. These assets are small and used throughout the UI.
@MainActor
@Observable
final class EssentialAssetsDownloadService {
    private let store = EssentialImageStore.shared

    private(set) var brandsDownloading: Set<TCGBrand> = []

    private var downloadTasks: [TCGBrand: Task<Void, Never>] = [:]

    /// First-launch: starts a download task per brand only if one isn't already running.
    func downloadIfNeeded(for brands: Set<TCGBrand>, nationalDexPokemon: [NationalDexPokemon]) {
        for brand in brands {
            guard downloadTasks[brand] == nil else { continue }
            schedule(brand: brand, nationalDexPokemon: nationalDexPokemon)
        }
    }

    /// Post-catalog-sync: cancels any in-progress task and restarts to pick up new sets/pokémon.
    func scheduleRecheck(for brands: Set<TCGBrand>, nationalDexPokemon: [NationalDexPokemon]) {
        for brand in brands {
            downloadTasks[brand]?.cancel()
            downloadTasks[brand] = nil
            schedule(brand: brand, nationalDexPokemon: nationalDexPokemon)
        }
    }

    private func schedule(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon]) {
        let task = Task {
            await self.performDownload(brand: brand, nationalDexPokemon: nationalDexPokemon)
        }
        downloadTasks[brand] = task
    }

    private func performDownload(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon]) async {
        brandsDownloading.insert(brand)
        defer {
            brandsDownloading.remove(brand)
            downloadTasks[brand] = nil
        }

        let desired = await buildEssentialList(brand: brand, nationalDexPokemon: nationalDexPokemon)
        guard !desired.isEmpty else { return }

        let toFetch = desired.filter { !store.hasEntry(relativePath: $0.key, brand: brand) }
        guard !toFetch.isEmpty else { return }

        var completed = 0
        await withTaskGroup(of: Void.self) { group in
            var iterator = toFetch.makeIterator()
            let initial = min(4, toFetch.count)
            for _ in 0..<initial {
                guard let item = iterator.next() else { break }
                group.addTask { await Self.downloadAndSave(key: item.key, url: item.url, brand: brand) }
            }
            for await _ in group {
                completed += 1
                if Task.isCancelled {
                    try? store.flushManifest(for: brand)
                    group.cancelAll()
                    return
                }
                if completed.isMultiple(of: 50) {
                    try? store.flushManifest(for: brand)
                }
                if let item = iterator.next() {
                    group.addTask { await Self.downloadAndSave(key: item.key, url: item.url, brand: brand) }
                }
            }
        }

        try? store.flushManifest(for: brand)
    }

    private func buildEssentialList(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon]) async -> [(key: String, url: URL)] {
        try? await CatalogStore.shared.open()
        var rows: [(key: String, url: URL)] = []
        var seen = Set<String>()

        func append(_ rawKey: String, _ url: URL) {
            let key = OfflineImageCanonicalKey.normalize(rawKey)
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            rows.append((key, url))
        }

        // Set logos and symbols
        let sets = (try? await CatalogStore.shared.fetchAllSets(for: brand)) ?? []
        for s in sets {
            let logo = s.logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !logo.isEmpty, let u = AppConfiguration.setLogoURLCandidates(logoSrc: logo).first {
                append(logo, u)
            }
            if let sym = s.symbolSrc?.trimmingCharacters(in: .whitespacesAndNewlines), !sym.isEmpty,
               let u = AppConfiguration.setSymbolURLCandidates(symbolSrc: sym).first {
                append(sym, u)
            }
        }

        // Pokémon national dex art (Pokémon brand only)
        if brand == .pokemon {
            for row in nationalDexPokemon {
                let rel = AppConfiguration.pokemonArtRelativePath(imageFileName: row.imageUrl)
                append(rel, AppConfiguration.pokemonArtURL(imageFileName: row.imageUrl))
            }
        }

        return rows
    }

    private nonisolated static func downloadAndSave(key: String, url: URL, brand: TCGBrand) async {
        guard let data = try? await fetchData(from: url) else { return }
        try? EssentialImageStore.shared.save(data: data, relativePath: key, brand: brand)
    }

    private nonisolated static func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await AppURLSession.images.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
