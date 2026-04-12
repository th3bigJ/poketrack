import Foundation
import Observation

/// User defaults for per-brand offline image packs and strict “offline mode” (no CDN fallback).
@Observable
@MainActor
final class OfflineImageSettings {
    private static let packPokemonKey = "offline_pack_pokemon"
    private static let packOnePieceKey = "offline_pack_onepiece"
    private static let packLorcanaKey = "offline_pack_lorcana"
    private static let strictOfflineKey = "offline_strict_no_cdn"

    /// When true, the user wants that brand’s images downloaded and kept on disk (Wi‑Fi only).
    private(set) var offlinePackEnabled: [TCGBrand: Bool] = [:]

    /// Side menu: when true, image views must not hit R2 for catalog assets (only local pack / placeholders).
    var strictOfflineImageMode: Bool {
        didSet { UserDefaults.standard.set(strictOfflineImageMode, forKey: Self.strictOfflineKey) }
    }

    init() {
        let d = UserDefaults.standard
        // `bool(forKey:)` matches how we persist with `set(_:forKey:)` and avoids stale `as? Bool` casts.
        strictOfflineImageMode = d.bool(forKey: Self.strictOfflineKey)
        offlinePackEnabled = [
            .pokemon: d.object(forKey: Self.packPokemonKey) as? Bool ?? false,
            .onePiece: d.object(forKey: Self.packOnePieceKey) as? Bool ?? false,
            .lorcana: d.object(forKey: Self.packLorcanaKey) as? Bool ?? false,
        ]
    }

    func isOfflinePackEnabled(for brand: TCGBrand) -> Bool {
        offlinePackEnabled[brand] ?? false
    }

    func setOfflinePackEnabled(_ enabled: Bool, for brand: TCGBrand) {
        offlinePackEnabled[brand] = enabled
        switch brand {
        case .pokemon: UserDefaults.standard.set(enabled, forKey: Self.packPokemonKey)
        case .onePiece: UserDefaults.standard.set(enabled, forKey: Self.packOnePieceKey)
        case .lorcana: UserDefaults.standard.set(enabled, forKey: Self.packLorcanaKey)
        }
    }
}

enum OfflinePackDownloadSizeCopy {
    /// Shown next to the Account toggle; totals from your R2 inventory (rough).
    static func approximateLabel(for brand: TCGBrand) -> String {
        switch brand {
        case .pokemon: return "~3.5 GB"
        case .onePiece: return "~700 MB"
        case .lorcana: return "~600 MB"
        }
    }
}
