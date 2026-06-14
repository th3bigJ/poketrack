import Foundation
import Observation

/// User defaults for the Pokemon offline image pack and strict "offline mode" (no CDN fallback).
@Observable
@MainActor
final class OfflineImageSettings {
    private static let packPokemonKey = "offline_pack_pokemon"
    private static let strictOfflineKey = "offline_strict_no_cdn"

    private(set) var isOfflinePackEnabledForPokemon: Bool

    var strictOfflineImageMode: Bool {
        didSet {
            UserDefaults.standard.set(strictOfflineImageMode, forKey: Self.strictOfflineKey)
            AppPreferencesBackup.notifyDidChange()
        }
    }

    init() {
        let d = UserDefaults.standard
        strictOfflineImageMode = d.bool(forKey: Self.strictOfflineKey)
        isOfflinePackEnabledForPokemon = d.object(forKey: Self.packPokemonKey) as? Bool ?? false

        NotificationCenter.default.addObserver(
            forName: .appPreferencesDidRestore,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromUserDefaults()
            }
        }
    }

    func reloadFromUserDefaults() {
        let d = UserDefaults.standard
        let strict = d.bool(forKey: Self.strictOfflineKey)
        let packEnabled = d.object(forKey: Self.packPokemonKey) as? Bool ?? false
        if strictOfflineImageMode != strict {
            strictOfflineImageMode = strict
        }
        if isOfflinePackEnabledForPokemon != packEnabled {
            isOfflinePackEnabledForPokemon = packEnabled
        }
    }

    func isOfflinePackEnabled(for brand: TCGBrand) -> Bool {
        isOfflinePackEnabledForPokemon
    }

    func setOfflinePackEnabled(_ enabled: Bool, for brand: TCGBrand) {
        isOfflinePackEnabledForPokemon = enabled
        UserDefaults.standard.set(enabled, forKey: Self.packPokemonKey)
        AppPreferencesBackup.notifyDidChange()
    }
}

enum OfflinePackDownloadSizeCopy {
    static func approximateLabel(for brand: TCGBrand) -> String { "~3.5 GB" }
}
