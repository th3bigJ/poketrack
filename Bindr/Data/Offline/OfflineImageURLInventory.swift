import Foundation

/// Builds the canonical (key, URL) pairs to download for an offline pack.
enum OfflineImageURLInventory {
    static func buildDesiredList(brand: TCGBrand, nationalDexPokemon: [NationalDexPokemon]) throws -> [(key: String, url: URL)] {
        try CatalogStore.shared.open()
        var rows: [(String, URL)] = []
        var seen = Set<String>()

        func append(_ rawKey: String, _ url: URL) {
            let key = OfflineImageCanonicalKey.normalize(rawKey)
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            rows.append((key, url))
        }

        switch brand {
        case .pokemon:
            let cards = try CatalogStore.shared.fetchAllCards(for: .pokemon)
            for c in cards {
                append(c.imageLowSrc, AppConfiguration.imageURL(relativePath: c.imageLowSrc))
            }
            let sets = try CatalogStore.shared.fetchAllSets(for: .pokemon)
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

        case .onePiece:
            let cards = try CatalogStore.shared.fetchAllCards(for: .onePiece)
            for c in cards {
                append(c.imageLowSrc, AppConfiguration.imageURL(relativePath: c.imageLowSrc))
            }
            let sets = try CatalogStore.shared.fetchAllSets(for: .onePiece)
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

        case .lorcana:
            let cards = try CatalogStore.shared.fetchAllCards(for: .lorcana)
            for c in cards {
                append(c.imageLowSrc, AppConfiguration.imageURL(relativePath: c.imageLowSrc))
            }
            let sets = try CatalogStore.shared.fetchAllSets(for: .lorcana)
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
        }

        return rows
    }
}
