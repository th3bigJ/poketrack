import Foundation
import Observation

/// Downloader for per-brand offline image packs; reconciles after catalog sync.
@MainActor
@Observable
final class OfflineImageDownloadService {
    private let store = OfflineImageStore.shared
    private let settings: OfflineImageSettings

    private static let maxConcurrentImageDownloads = 4

    /// Short status for Account UI (per brand).
    private(set) var statusLine: [TCGBrand: String] = [:]
    /// Bumped when any pack write finishes so `CachedAsyncImage` can reload from disk.
    private(set) var packDataRevision: Int = 0
    /// Brands with an active download task.
    private(set) var brandsDownloadingImages: Set<TCGBrand> = []

    private var downloadTasks: [TCGBrand: Task<Void, Never>] = [:]

    init(settings: OfflineImageSettings) {
        self.settings = settings
    }

    func cancelDownload(for brand: TCGBrand) {
        downloadTasks[brand]?.cancel()
        downloadTasks[brand] = nil
        statusLine[brand] = nil
    }

    /// Call after deleting a pack from disk so image views reload.
    func notifyPackMutated() {
        packDataRevision += 1
    }

    /// Full download or top-up after the user enables the pack toggle.
    func runFullDownloadIfNeeded(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon], sealedProducts: [SealedProduct]) async {
        guard settings.isOfflinePackEnabled(for: brand) else { return }
        cancelDownload(for: brand)
        let task = Task {
            await self.performDownload(brand: brand, nationalDexPokemon: nationalDexPokemon, sealedProducts: sealedProducts, pruneOrphans: true)
        }
        downloadTasks[brand] = task
        await task.value
        downloadTasks[brand] = nil
    }

    /// After catalog sync adds/removes cards, refresh local files for every brand with the pack enabled.
    func reconcileAfterCatalogSync(enabledBrands: Set<TCGBrand>, nationalDexPokemon: [NationalDexPokemon], sealedProducts: [SealedProduct]) async {
        let brands = enabledBrands.filter { settings.isOfflinePackEnabled(for: $0) }
        await withTaskGroup(of: Void.self) { group in
            for brand in brands {
                group.addTask {
                    await self.performDownload(brand: brand, nationalDexPokemon: nationalDexPokemon, sealedProducts: sealedProducts, pruneOrphans: true)
                }
            }
        }
    }

    private func performDownload(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon], sealedProducts: [SealedProduct], pruneOrphans: Bool) async {
        guard settings.isOfflinePackEnabled(for: brand) else { return }
        brandsDownloadingImages.insert(brand)
        defer { brandsDownloadingImages.remove(brand) }

        // Ensure all sets have cards in the catalog before building the image inventory.
        // Sets with no cards are skipped by the normal sync (only downloaded on first install).
        let missingBefore = (try? await CatalogStore.shared.fetchSetCodesWithNoCards(for: brand))?.count ?? 0
        statusLine[brand] = "Completing catalog (\(missingBefore) sets missing)…"
        await CatalogSyncCoordinator.shared.fillMissingSetCards(for: brand)
        let missingAfter = (try? await CatalogStore.shared.fetchSetCodesWithNoCards(for: brand))?.count ?? 0
        statusLine[brand] = "Catalogued. \(missingBefore - missingAfter) sets filled, \(missingAfter) still empty. Building list…"

        let desired: [(String, URL)]
        do {
            desired = try await OfflineImageURLInventory.buildDesiredList(brand: brand, nationalDexPokemon: nationalDexPokemon, sealedProducts: sealedProducts)
        } catch {
            statusLine[brand] = "Could not read catalog."
            return
        }
        statusLine[brand] = "Found \(desired.count) images to check…"

        // Reconciling the desired list against what's already on disk is pure filesystem work
        // (a manifest lookup + an existence check per item). With 1000+ items this previously ran
        // on the main actor and froze the UI for ~8s. `OfflineImageStore` is thread-safe
        // (@unchecked Sendable, serialised internally), so do the prune + diff on a background
        // task and only hop back to the main actor with the results.
        let store = self.store
        let (toFetch, didMutatePack): ([(String, URL)], Bool) = await Task.detached(priority: .utility) {
            let desiredKeys = Set(desired.map(\.0))
            var didMutate = false
            if pruneOrphans {
                let existing = store.manifestKeys(for: brand)
                for orphan in existing.subtracting(desiredKeys) {
                    guard store.hasEntry(relativePath: orphan, brand: brand) else { continue }
                    do {
                        try store.removeEntry(relativePath: orphan, brand: brand)
                        didMutate = true
                    } catch {
                        // Disk / manifest race — skip; next reconcile can retry.
                    }
                }
            }
            let toFetch = desired.filter { !store.hasEntry(relativePath: $0.0, brand: brand) }
            return (toFetch, didMutate)
        }.value
        if toFetch.isEmpty {
            statusLine[brand] = "Offline images ready."
            if didMutatePack {
                packDataRevision += 1
            }
            return
        }

        var completed = 0
        let total = toFetch.count

        await withTaskGroup(of: Bool.self) { group in
            var iterator = toFetch.makeIterator()
            let initial = min(Self.maxConcurrentImageDownloads, total)

            for _ in 0..<initial {
                guard let (key, url) = iterator.next() else { break }
                group.addTask {
                    if Task.isCancelled { return false }
                    return await Self.downloadAndSave(key: key, url: url, brand: brand)
                }
            }

            for await _ in group {
                if Task.isCancelled { group.cancelAll(); return }
                completed += 1
                // Throttle: writing to @Observable on @MainActor on every image notifies
                // the entire SwiftUI tree. Update every 25 images (~2.5% steps) instead.
                if completed.isMultiple(of: 25) || completed == total {
                    statusLine[brand] = "Downloading… \(completed)/\(total)"
                }
                // Flush manifest every 500 saves to persist progress without hammering disk.
                if completed.isMultiple(of: 500) {
                    try? OfflineImageStore.shared.flushManifest(for: brand)
                }
                if let (key, url) = iterator.next() {
                    group.addTask {
                        if Task.isCancelled { return false }
                        return await Self.downloadAndSave(key: key, url: url, brand: brand)
                    }
                }
            }
        }

        if Task.isCancelled {
            // Flush whatever was saved before cancellation so progress isn't lost.
            try? OfflineImageStore.shared.flushManifest(for: brand)
            return
        }

        try? OfflineImageStore.shared.flushManifest(for: brand)
        statusLine[brand] = "Offline images ready."
        packDataRevision += 1
    }

    /// Network + disk write off the main actor so many images can load in parallel.
    private nonisolated static func downloadAndSave(key: String, url: URL, brand: TCGBrand) async -> Bool {
        var urls = [url]
        if key.contains("upcoming/") {
            let imageSrc: String
            if let range = key.range(of: "upcoming/") {
                imageSrc = String(key[range.lowerBound...])
            } else {
                imageSrc = key
            }
            let candidates = AppConfiguration.upcomingReleaseImageURLCandidates(imageSrc: imageSrc)
            if !candidates.isEmpty {
                urls = candidates
            }
        }

        for candidate in urls {
            do {
                let data = try await fetchImageData(from: candidate)
                try OfflineImageStore.shared.save(data: data, relativePath: key, brand: brand)
                return true
            } catch {
                continue
            }
        }
        return false
    }

    private nonisolated static func fetchImageData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await AppURLSession.images.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return data
    }
}
