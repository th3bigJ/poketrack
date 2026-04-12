import CryptoKit
import Foundation

/// Normalized key for manifest + disk lookup (matches `Card.imageLowSrc`, `TCGSet.logoSrc`, etc. without leading slashes).
enum OfflineImageCanonicalKey {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^/+", with: "", options: .regularExpression)
    }
}

private struct OfflinePackManifest: Codable {
    /// Canonical relative path → stored filename under `files/`.
    var entries: [String: String]
}

/// On-disk store for optional per-brand offline image packs (not `URLCache` — survives eviction and supports deterministic deletes).
final class OfflineImageStore: @unchecked Sendable {
    static let shared = OfflineImageStore()

    private let io = DispatchQueue(label: "com.bindr.offlineimages", qos: .utility)
    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Avoid re-reading `manifest.json` from disk for every thumbnail lookup while scrolling.
    private var manifestMemoryCache: [TCGBrand: OfflinePackManifest] = [:]

    private init() {}

    private func rootDir() throws -> URL {
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Bindr", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("OfflineMedia", isDirectory: true)
    }

    private func brandDir(for brand: TCGBrand) throws -> URL {
        let r = try rootDir()
        try fm.createDirectory(at: r, withIntermediateDirectories: true)
        let d = r.appendingPathComponent(brand.rawValue, isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func manifestURL(for brand: TCGBrand) throws -> URL {
        try brandDir(for: brand).appendingPathComponent("manifest.json", isDirectory: false)
    }

    private func filesDir(for brand: TCGBrand) throws -> URL {
        let d = try brandDir(for: brand).appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Returns on-disk file URL if the manifest contains this canonical key.
    func localFileURL(relativePath: String, brand: TCGBrand) -> URL? {
        let key = OfflineImageCanonicalKey.normalize(relativePath)
        guard !key.isEmpty else { return nil }
        return io.sync {
            guard let manifest = loadManifestLocked(for: brand),
                  let name = manifest.entries[key],
                  !name.isEmpty
            else { return nil }
            let url = (try? filesDir(for: brand))?.appendingPathComponent(name, isDirectory: false)
            guard let url, fm.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    func hasEntry(relativePath: String, brand: TCGBrand) -> Bool {
        localFileURL(relativePath: relativePath, brand: brand) != nil
    }

    /// Writes bytes for a canonical catalog-relative key and updates the manifest.
    func save(data: Data, relativePath: String, brand: TCGBrand) throws {
        let key = OfflineImageCanonicalKey.normalize(relativePath)
        guard !key.isEmpty else { return }
        try io.sync {
            var manifest = loadManifestLocked(for: brand) ?? OfflinePackManifest(entries: [:])
            let files = try filesDir(for: brand)
            let ext = (key as NSString).pathExtension
            let baseName: String
            if ext.isEmpty {
                baseName = Self.stableFileName(for: key)
            } else {
                baseName = Self.stableFileName(for: key) + "." + ext
            }
            let dest = files.appendingPathComponent(baseName, isDirectory: false)
            try data.write(to: dest, options: .atomic)
            manifest.entries[key] = baseName
            try saveManifestLocked(manifest, brand: brand)
        }
    }

    /// Removes every file + manifest for a franchise.
    func deleteAll(for brand: TCGBrand) throws {
        try io.sync {
            manifestMemoryCache.removeValue(forKey: brand)
            let dir = try brandDir(for: brand)
            if fm.fileExists(atPath: dir.path) {
                try fm.removeItem(at: dir)
            }
        }
    }

    /// Drops one manifest entry and its file (used when catalog removes a card image).
    func removeEntry(relativePath: String, brand: TCGBrand) throws {
        let key = OfflineImageCanonicalKey.normalize(relativePath)
        guard !key.isEmpty else { return }
        try io.sync {
            guard var manifest = loadManifestLocked(for: brand),
                  let name = manifest.entries.removeValue(forKey: key)
            else { return }
            let file = try filesDir(for: brand).appendingPathComponent(name, isDirectory: false)
            if fm.fileExists(atPath: file.path) {
                try fm.removeItem(at: file)
            }
            try saveManifestLocked(manifest, brand: brand)
        }
    }

    func manifestKeys(for brand: TCGBrand) -> Set<String> {
        io.sync {
            guard let m = loadManifestLocked(for: brand) else { return [] }
            return Set(m.entries.keys)
        }
    }

    private func loadManifestLocked(for brand: TCGBrand) -> OfflinePackManifest? {
        if let cached = manifestMemoryCache[brand] { return cached }
        guard let url = try? manifestURL(for: brand),
              let data = try? Data(contentsOf: url),
              let m = try? decoder.decode(OfflinePackManifest.self, from: data)
        else { return nil }
        manifestMemoryCache[brand] = m
        return m
    }

    private func saveManifestLocked(_ manifest: OfflinePackManifest, brand: TCGBrand) throws {
        let url = try manifestURL(for: brand)
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
        manifestMemoryCache[brand] = manifest
    }

    private static func stableFileName(for canonicalKey: String) -> String {
        let data = Data(canonicalKey.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
