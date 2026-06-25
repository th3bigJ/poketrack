import CryptoKit
import Foundation

/// Stores set logos, set symbols, and Pokémon art that are downloaded on first launch regardless
/// of whether the user has enabled the offline image pack. Lives under
/// `OfflineMedia/essential/{brand}/` — separate from the user-toggled pack so it is never
/// deleted when the user disables offline mode.
final class EssentialImageStore: @unchecked Sendable {
    static let shared = EssentialImageStore()

    private let io = DispatchQueue(label: "com.bindr.essentialimages", qos: .utility)
    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var manifestMemoryCache: [TCGBrand: EssentialManifest] = [:]
    private var filesDirCache: [TCGBrand: URL] = [:]

    private init() {}

    // MARK: - Paths

    private func rootDir(create: Bool) throws -> URL {
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ).appendingPathComponent("Bindr/OfflineMedia/essential", isDirectory: true)
        if create {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private func brandDir(for brand: TCGBrand, create: Bool) throws -> URL {
        let d = try rootDir(create: create).appendingPathComponent(brand.rawValue, isDirectory: true)
        if create {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private func filesDir(for brand: TCGBrand, create: Bool) throws -> URL {
        let d = try brandDir(for: brand, create: create).appendingPathComponent("files", isDirectory: true)
        if create {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private func manifestURL(for brand: TCGBrand, create: Bool = true) throws -> URL {
        try brandDir(for: brand, create: create).appendingPathComponent("manifest.json", isDirectory: false)
    }

    // MARK: - Public API

    func localFileURL(relativePath: String, brand: TCGBrand) -> URL? {
        let key = OfflineImageCanonicalKey.normalize(relativePath)
        guard !key.isEmpty else { return nil }
        return io.sync {
            guard let manifest = loadManifestLocked(for: brand),
                  let name = manifest.entries[key],
                  !name.isEmpty
            else { return nil }
            // Trust the manifest — files are only removed via removeEntry/deleteAll which
            // also update the manifest, so a present entry means the file exists.
            let dir = filesDirCache[brand] ?? (try? filesDir(for: brand, create: false))
            if filesDirCache[brand] == nil { filesDirCache[brand] = dir }
            return dir?.appendingPathComponent(name, isDirectory: false)
        }
    }

    func hasEntry(relativePath: String, brand: TCGBrand) -> Bool {
        localFileURL(relativePath: relativePath, brand: brand) != nil
    }

    func save(data: Data, relativePath: String, brand: TCGBrand) throws {
        let key = OfflineImageCanonicalKey.normalize(relativePath)
        guard !key.isEmpty else { return }
        let ext = (key as NSString).pathExtension
        let baseName = ext.isEmpty ? stableFileName(for: key) : stableFileName(for: key) + "." + ext
        let files = try filesDir(for: brand, create: true)
        let dest = files.appendingPathComponent(baseName, isDirectory: false)
        try data.write(to: dest, options: .atomic)
        io.sync {
            var manifest = manifestMemoryCache[brand] ?? EssentialManifest(entries: [:])
            manifest.entries[key] = baseName
            manifestMemoryCache[brand] = manifest
        }
    }

    func flushManifest(for brand: TCGBrand) throws {
        let snapshot: EssentialManifest? = io.sync { manifestMemoryCache[brand] }
        guard let snapshot else { return }
        let url = try manifestURL(for: brand, create: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Private

    private func loadManifestLocked(for brand: TCGBrand) -> EssentialManifest? {
        if let cached = manifestMemoryCache[brand] { return cached }
        guard let url = try? manifestURL(for: brand, create: false),
              let data = try? Data(contentsOf: url),
              let m = try? decoder.decode(EssentialManifest.self, from: data)
        else { return nil }
        manifestMemoryCache[brand] = m
        return m
    }

    private func stableFileName(for key: String) -> String {
        let data = Data(key.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

private struct EssentialManifest: Codable {
    var entries: [String: String]
}
