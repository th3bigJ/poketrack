import Foundation
import Network
import Observation

/// Wi‑Fi–only downloader for per-brand offline image packs; reconciles after catalog sync.
@MainActor
@Observable
final class OfflineImageDownloadService {
    private let store = OfflineImageStore.shared
    private let settings: OfflineImageSettings
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let wifiQueue = DispatchQueue(label: "com.bindr.offline.wifi")

    /// Matches ``AppURLSession`` `httpMaximumConnectionsPerHost` — good parallelism without overwhelming R2.
    private static let maxConcurrentImageDownloads = 10

    private(set) var isWiFiAvailable = false
    /// Short status for Account UI (per brand).
    private(set) var statusLine: [TCGBrand: String] = [:]
    /// Bumped when any pack write finishes so `CachedAsyncImage` can reload from disk.
    private(set) var packDataRevision: Int = 0

    private var downloadTasks: [TCGBrand: Task<Void, Never>] = [:]

    init(settings: OfflineImageSettings) {
        self.settings = settings
        wifiMonitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in
                self?.isWiFiAvailable = ok
            }
        }
        wifiMonitor.start(queue: wifiQueue)
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
    func runFullDownloadIfNeeded(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon]) async {
        guard settings.isOfflinePackEnabled(for: brand) else { return }
        cancelDownload(for: brand)
        let task = Task {
            await self.performDownload(brand: brand, nationalDexPokemon: nationalDexPokemon, pruneOrphans: true)
        }
        downloadTasks[brand] = task
        await task.value
        downloadTasks[brand] = nil
    }

    /// After catalog sync adds/removes cards, refresh local files for every brand with the pack enabled.
    func reconcileAfterCatalogSync(enabledBrands: Set<TCGBrand>, nationalDexPokemon: [NationalDexPokemon]) async {
        for brand in enabledBrands where settings.isOfflinePackEnabled(for: brand) {
            await performDownload(brand: brand, nationalDexPokemon: nationalDexPokemon, pruneOrphans: true)
        }
    }

    private func performDownload(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon], pruneOrphans: Bool) async {
        guard settings.isOfflinePackEnabled(for: brand) else { return }

        let desired: [(String, URL)]
        do {
            desired = try OfflineImageURLInventory.buildDesiredList(brand: brand, nationalDexPokemon: nationalDexPokemon)
        } catch {
            statusLine[brand] = "Could not read catalog."
            return
        }

        let desiredKeys = Set(desired.map(\.0))
        var didMutatePack = false
        if pruneOrphans {
            let existing = store.manifestKeys(for: brand)
            for orphan in existing.subtracting(desiredKeys) {
                guard store.hasEntry(relativePath: orphan, brand: brand) else { continue }
                do {
                    try store.removeEntry(relativePath: orphan, brand: brand)
                    didMutatePack = true
                } catch {
                    // Disk / manifest race — skip; next reconcile can retry.
                }
            }
        }

        let toFetch = desired.filter { !store.hasEntry(relativePath: $0.0, brand: brand) }
        if toFetch.isEmpty {
            statusLine[brand] = "Offline images ready."
            // Do not bump revision when nothing changed — otherwise every app launch re-runs every
            // `CachedAsyncImage` / `ProgressiveAsyncImage` task and feels like images re-download.
            if didMutatePack {
                packDataRevision += 1
            }
            return
        }

        let wifiWait: @Sendable () async -> Void = { [weak self] in
            while await MainActor.run(body: {
                guard let self else { return false }
                return !self.isWiFiAvailable
            }) {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        var completed = 0
        let total = toFetch.count

        await withTaskGroup(of: Bool.self) { group in
            var iterator = toFetch.makeIterator()
            let initial = min(Self.maxConcurrentImageDownloads, total)

            for _ in 0..<initial {
                guard let (key, url) = iterator.next() else { break }
                group.addTask {
                    await wifiWait()
                    if Task.isCancelled { return false }
                    return await Self.downloadAndSave(key: key, url: url, brand: brand)
                }
            }

            for await _ in group {
                if Task.isCancelled { group.cancelAll(); return }
                completed += 1
                statusLine[brand] = "Downloading… \(completed)/\(total)"
                if let (key, url) = iterator.next() {
                    group.addTask {
                        await wifiWait()
                        if Task.isCancelled { return false }
                        return await Self.downloadAndSave(key: key, url: url, brand: brand)
                    }
                }
            }
        }

        if Task.isCancelled {
            return
        }

        statusLine[brand] = "Offline images ready."
        packDataRevision += 1
    }

    /// Network + disk write off the main actor so many images can load in parallel.
    private nonisolated static func downloadAndSave(key: String, url: URL, brand: TCGBrand) async -> Bool {
        do {
            let data = try await fetchImageData(from: url)
            try OfflineImageStore.shared.save(data: data, relativePath: key, brand: brand)
            return true
        } catch {
            return false
        }
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
