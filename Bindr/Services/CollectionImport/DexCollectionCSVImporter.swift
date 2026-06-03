import Foundation

/// Parses collection export CSV files from the [Dex](https://dex.tcg) app.
enum DexCollectionCSVImporter {

    struct Row: Sendable {
        /// Dex `Id` column — matches catalog ``Card/externalId`` (not ``Card/masterCardId``).
        let cardID: String
        let variantDisplayName: String
        let quantity: Int
        let cardName: String?
    }

    struct ParseResult: Sendable {
        let rows: [Row]
        let skippedZeroQuantity: Int
        let skippedInvalidRows: Int
    }

    enum ImportError: LocalizedError {
        case unreadableFile
        case missingColumns(Set<String>)
        case noImportableRows

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "Could not read the CSV file."
            case .missingColumns(let cols):
                return "This file is missing required columns: \(cols.sorted().joined(separator: ", "))."
            case .noImportableRows:
                return "No rows with quantity greater than zero were found."
            }
        }
    }

    private static let requiredColumns: Set<String> = ["Id", "Variant", "Quantity"]

    static func parse(fileURL: URL) throws -> ParseResult {
        let data = try Data(contentsOf: fileURL)
        guard let text = decodeText(from: data), !text.isEmpty else {
            throw ImportError.unreadableFile
        }

        let records = parseSemicolonCSV(text)
        guard !records.isEmpty else { throw ImportError.noImportableRows }

        let header = Set(records[0].keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let missing = requiredColumns.subtracting(header)
        if !missing.isEmpty { throw ImportError.missingColumns(missing) }

        var rows: [Row] = []
        var skippedZero = 0
        var skippedInvalid = 0

        for record in records.dropFirst() {
            let type = record["Type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let type, !type.isEmpty, type != "collection" { continue }

            let cardID = record["Id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let variant = record["Variant"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cardID.isEmpty, !variant.isEmpty else {
                skippedInvalid += 1
                continue
            }

            let qtyRaw = record["Quantity"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let quantity = Int(qtyRaw) else {
                skippedInvalid += 1
                continue
            }
            guard quantity > 0 else {
                skippedZero += 1
                continue
            }

            let name = record["Name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(Row(
                cardID: cardID,
                variantDisplayName: variant,
                quantity: quantity,
                cardName: name?.isEmpty == false ? name : nil
            ))
        }

        guard !rows.isEmpty else { throw ImportError.noImportableRows }
        return ParseResult(rows: rows, skippedZeroQuantity: skippedZero, skippedInvalidRows: skippedInvalid)
    }

    /// Maps Dex “Variant” labels to catalog pricing variant keys when possible.
    static func variantKey(forDexVariant displayName: String, availableKeys: [String]) -> String {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = staticVariantMap[normalized], availableKeys.isEmpty || availableKeys.contains(mapped) {
            return mapped
        }

        let targetSlug = slug(normalized)
        if let exact = availableKeys.first(where: { $0.lowercased() == targetSlug }) {
            return exact
        }

        if let labelMatch = availableKeys.first(where: { variantDisplayLabel($0).compare(normalized, options: .caseInsensitive) == .orderedSame }) {
            return labelMatch
        }

        if let contains = availableKeys.first(where: {
            let labelSlug = slug(variantDisplayLabel($0))
            return labelSlug == targetSlug || labelSlug.contains(targetSlug) || targetSlug.contains(labelSlug)
        }) {
            return contains
        }

        return staticVariantMap[normalized] ?? (availableKeys.first ?? "normal")
    }

    // MARK: - Private

    private static let staticVariantMap: [String: String] = [
        "Normal": "normal",
        "Holo": "holofoil",
        "Reverse Holo": "reverseHolofoil",
        "Cosmos Holo": "cosmosHolofoil",
        "1st Edition": "firstEdition",
        "Pokémon Center": "pokemonCenterStamp",
        "Pokemon Center": "pokemonCenterStamp",
        "Play! Pokémon": "playPokemonStamp",
        "Play! Pokemon": "playPokemonStamp",
        "Pokémon Horizons": "pokemonHorizonsStamp",
        "Pokemon Horizons": "pokemonHorizonsStamp",
        "Professor Program": "professorProgramStamp",
        "Expansion Stamp": "expansionStamp",
        "Jumbo": "jumbo",
        "Jumbo (Expansion Stamp)": "jumboExpansionStamp",
        "Trick or Trade 2024": "trickOrTrade2024",
        "Holiday Calendar 2022": "holidayCalendar2022",
        "EB Games": "ebGamesStamp",
        "GameStop": "gameStopStamp",
    ]

    private static func decodeText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16), !utf16.isEmpty { return utf16 }
        if let utf16LE = String(data: data, encoding: .utf16LittleEndian), !utf16LE.isEmpty { return utf16LE }
        return String(data: data, encoding: .macOSRoman)
    }

    private static func parseSemicolonCSV(_ text: String) -> [[String: String]] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }

        let headers = headerLine.split(separator: ";", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var records: [[String: String]] = []
        for line in lines.dropFirst() {
            let fields = line.split(separator: ";", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            var record: [String: String] = [:]
            for (index, header) in headers.enumerated() where !header.isEmpty {
                record[header] = index < fields.count ? fields[index] : ""
            }
            records.append(record)
        }
        return records
    }

    private static func slug(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "!", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func variantDisplayLabel(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
