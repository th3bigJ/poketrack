import Foundation

/// Row from catalog `pokemon.json` on R2 (`nationalDexNumber` sort order for browsing).
struct NationalDexPokemon: Codable, Identifiable, Hashable, Sendable {
    let nationalDexNumber: Int
    let name: String
    let imageUrl: String
    let generation: Int?

    var id: Int { nationalDexNumber }

    /// Human-readable title from kebab-case `name` (e.g. `mr-mime` → `Mr Mime`).
    var displayName: String {
        name
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { part in
                let s = String(part)
                guard let first = s.first else { return s }
                return String(first).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
