import Foundation

/// Builds the canonical (key, URL) pairs to download for an offline pack.
enum OfflineImageURLInventory {
    static func buildDesiredList(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon], sealedProducts: [SealedProduct]) async throws -> [(key: String, url: URL)] {
        try await CatalogStore.shared.open()
        var rows: [(String, URL)] = []
        var seen = Set<String>()

        func append(_ rawKey: String, _ url: URL) {
            let key = OfflineImageCanonicalKey.normalize(rawKey)
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            rows.append((key, url))
        }

        let cards = try await CatalogStore.shared.fetchAllCards(for: .pokemon)
        for c in cards {
            append(c.displayImageSrc, AppConfiguration.imageURL(relativePath: c.displayImageSrc))
        }
        let sets = try await CatalogStore.shared.fetchAllSets(for: .pokemon)
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
        for row in nationalDexPokemon {
            let rel = AppConfiguration.pokemonArtRelativePath(imageFileName: row.imageUrl)
            if rel.hasPrefix("http"), let u = URL(string: rel) {
                append(rel, u)
            } else {
                append(rel, AppConfiguration.pokemonArtURL(imageFileName: row.imageUrl))
            }
        }
        for product in sealedProducts where product.tcg == "pokemon" {
            guard let url = product.image?.resolvedURL else { continue }
            let key = AppConfiguration.offlineImageKey(for: url) ?? url.absoluteString
            append(key, url)
        }

        if let data = await CatalogStore.shared.dailyBlob(key: DailyBlobKey.upcomingReleases),
           let releases = UpcomingReleasesService.decode(data) {
            for release in releases {
                let imageSrc = release.image.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !imageSrc.isEmpty,
                      let url = AppConfiguration.upcomingReleaseImageURL(imageSrc: imageSrc) else { continue }
                let key = AppConfiguration.upcomingReleaseOfflineKey(imageSrc: imageSrc)
                    ?? AppConfiguration.offlineImageKey(for: url)
                    ?? imageSrc
                append(key, url)
            }
        }

        return rows
    }
}
