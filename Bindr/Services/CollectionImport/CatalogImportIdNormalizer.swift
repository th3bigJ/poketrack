import Foundation

/// Maps third-party export ids (e.g. Dex) to ids stored in our catalog (`externalId`, `setCode-localId`, …).
enum CatalogImportIdNormalizer {

    /// All catalog ids to try for one Dex row id, in priority order.
    static func lookupCandidates(for dexCatalogId: String) -> [String] {
        let trimmed = dexCatalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen = Set<String>()
        var out: [String] = []

        func append(_ value: String) {
            let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            let key = t.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(t)
        }

        append(trimmed)
        guard let dash = trimmed.firstIndex(of: "-") else { return out }

        let setPrefix = String(trimmed[..<dash]).lowercased()
        let localId = String(trimmed[trimmed.index(after: dash)...])

        for altPrefix in alternateSetPrefixes(for: setPrefix) {
            append("\(altPrefix)-\(localId)")
        }

        return out
    }

    /// Dex often omits `pt` for fractional Scarlet & Violet / Mega Evolution sets (`sv35` → `sv3pt5`).
    static func alternateSetPrefixes(for setPrefix: String) -> [String] {
        let lower = setPrefix.lowercased()
        var alts: [String] = []

        func append(_ prefix: String) {
            let p = prefix.lowercased()
            guard p != lower, !alts.contains(p) else { return }
            alts.append(p)
        }

        // Explicit Dex ↔ catalog set codes (Dex shorthand → our `setCode`).
        let explicitDexToCatalog: [String: String] = [
            "sv35": "sv3pt5",
            "sv45": "sv4pt5",
            "sv65": "sv6pt5",
            "sv85": "sv8pt5",
            "me25": "me2pt5",
        ]
        if let mapped = explicitDexToCatalog[lower] {
            append(mapped)
        }

        // Generic: `sv35` / `me25` → `sv3pt5` / `me2pt5` when Dex drops `pt` before the `.5` index.
        // Do not rewrite codes that are real set keys in our catalog (e.g. `swsh35`, `sm115`).
        if !expandedLegalSetKeys.contains(lower),
           let regex = try? NSRegularExpression(pattern: #"^(sv|me)(\d)5$"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           match.numberOfRanges == 3,
           let franchiseRange = Range(match.range(at: 1), in: lower),
           let majorRange = Range(match.range(at: 2), in: lower) {
            let franchise = String(lower[franchiseRange])
            let major = String(lower[majorRange])
            append("\(franchise)\(major)pt5")
        }

        return alts
    }
}
