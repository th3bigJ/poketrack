import Foundation
import Vision

/// Pulls **name**, **HP**, and **collection number** out of Vision OCR even though string order is arbitrary.
/// Center-band text is **Pokémon attacks** or, for Trainers, long **rules** (no attacks).
///
/// **Apple docs:** each `VNRecognizedTextObservation` has a normalized `boundingBox`; see
/// [Detecting Objects in Still Images](https://developer.apple.com/documentation/vision/original_objective-c_and_swift_api/recognizing_objects_in_an_image)
/// and [`VNRecognizedTextObservation`](https://developer.apple.com/documentation/vision/vnrecognizedtextobservation).
///
/// Vision gives each text fragment a `boundingBox` in **normalized image coordinates** (origin bottom-left, range 0…1).
/// On a typical Pokémon card photo in portrait:
/// - **Higher `midY`** → closer to the **physical top** of the card (name + HP band).
/// - **Lower `midY`** → closer to the **physical bottom** (set code / `062/193` strip).
/// - **Lower `midX`** → **left** (name); **higher `midX`** → **right** (HP).
///
/// We never rely on array order from Vision — only **position + regex** classification.
enum CardOCRFieldExtractor {

    struct ExtractedFields {
        var name: String?
        /// Numeric string only, e.g. `"120"`, when OCR found an HP line.
        var hp: String?
        /// e.g. `"062/193"`
        var setNumber: String?
        /// Illustrator line near the card footer, e.g. `"Kouki Saitou"`.
        var illustrator: String?
        /// Middle of the card: **attack names** on Pokémon, or **rules** on Trainers (often long; search uses partial token match).
        var centerSearchHint: String?
    }

    // MARK: - Regex

    /// Standard set/collector number on the card front.
    private static let setNumberRegex = try! NSRegularExpression(pattern: #"\b(\d{1,4}/\d{1,4})\b"#)
    /// Every `NN/NNN`-like substring in a blob (footer / flavor often garbled but still contains the real fraction).
    private static let looseFractionRegex = try! NSRegularExpression(pattern: #"(\d{2,3}/\d{2,3})"#)

    /// "HP 120", "HP120", "HP: 120"
    private static let hpLeadingRegex = try! NSRegularExpression(pattern: #"(?i)HP\s*:?\s*(\d{2,4})\b"#)
    /// "120 HP" (less common layout)
    private static let hpTrailingRegex = try! NSRegularExpression(pattern: #"(?i)^(\d{2,4})\s*HP\b"#)
    /// ".70" when OCR drops the leading digit before HP (reads as dot + tens)
    private static let hpDotLeadingRegex = try! NSRegularExpression(pattern: #"^\.(\d{2,4})$"#)
    /// "-70" when OCR captures a leading minus from the HP glyph
    private static let hpMinusLeadingRegex = try! NSRegularExpression(pattern: #"^-(\d{2,4})$"#)
    private static let illustratorInlineRegex = try! NSRegularExpression(
        pattern: #"(?i)^(?:illus\.?|illustrator)\s*:?\s*(.+)$"#
    )

    private static let noiseExactNames: Set<String> = [
        "basic", "basis", "basig", "basc",
        "stage", "stage 1", "stage 2", "stage 3", "stage1", "stage2", "stage3",
        "stagez", "stagex", "stage2.", "stage 2.", "stages",
        "pokémon", "pokemon", "trainer", "item", "supporter",
        "stadium", "energy", "illus", "illustrator", "©", "®",
    ]

    /// Strip stage / layout words and collapse whitespace for catalog search (does not change Vision extraction).
    private static let searchNoiseWordRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(?:basic|basis|stage\s*\d*)\b"#,
        options: []
    )

    /// Lines that are never the Pokémon name (stage markers, type abbreviations, etc.).
    private static let skipLineRegex = try! NSRegularExpression(
        pattern: #"^(?:\d+|HP\s*\d+|\d+\s*HP|[A-Z]{1,2}|Stage\w*\s*[\dz]?\.?|RETREAT|WEAKNESS|RESISTANCE|×\d|x\d|-\d+)$"#,
        options: .caseInsensitive
    )

    /// Headers / UI in the lower third that sometimes overlap the middle in photos.
    private static let centerBandNoiseRegex = try! NSRegularExpression(
        pattern: #"^(?:WEAKNESS|RESISTANCE|RETREAT|ILLUS\.|ILLUSTRATOR|©|®|Pokémon|Pokemon|TRAINER|ITEM|STADIUM|ENERGY)$"#,
        options: .caseInsensitive
    )

    // MARK: - Spatial bands (normalized Vision space)
    // Vision origin is bottom-left; Y=1.0 = physical top of card, Y=0.0 = physical bottom.
    //
    // Card layout (top→bottom):
    //   Name + HP:   top 20%  → Vision Y > 0.80
    //   Attacks:     50–85%   → Vision Y 0.15 … 0.50
    //   Card number: bottom 10% → Vision Y < 0.10

    /// Upper title band (name + HP): top 20% of the card.
    private static let topBandMinY: CGFloat = 0.80

    /// Attack / trainer-rules band: 50–85% from the top.
    private static let centerBandMinY: CGFloat = 0.15
    private static let centerBandMaxY: CGFloat = 0.50

    /// Name is usually on the left side of the title row.
    private static let nameLeftMaxX: CGFloat = 0.58
    /// HP is usually on the right.
    private static let hpRightMinX: CGFloat = 0.42

    // MARK: - Public

    /// Collects possible collector numbers from **all** OCR lines (including flavor text) for ranking.
    static func extractCardNumberCandidates(from rawLines: [String]) -> [String] {
        let blob = rawLines.joined(separator: " ")
        guard !blob.isEmpty else { return [] }
        var found = Set<String>()
        let nsBlob = blob as NSString
        let full = NSRange(location: 0, length: nsBlob.length)

        setNumberRegex.enumerateMatches(in: blob, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: blob) else { return }
            found.insert(String(blob[r]))
        }
        looseFractionRegex.enumerateMatches(in: blob, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: blob) else { return }
            found.insert(String(blob[r]))
        }
        return Array(found).sorted()
    }

    /// Removes **basic** / **basis** and extra spaces from a string used for **search** (raw OCR lines unchanged).
    static func filterSearchNoise(_ text: String?) -> String? {
        guard var t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        t = searchNoiseWordRegex.stringByReplacingMatches(in: t, range: range, withTemplate: " ")
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func extract(from observations: [VNRecognizedTextObservation]) -> ExtractedFields {
        let lines: [OCRLine] = observations.compactMap { obs in
            guard let recognized = obs.topCandidates(1).first else { return nil }
            let text = recognized.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, boundingBox: obs.boundingBox)
        }

        guard !lines.isEmpty else {
            return ExtractedFields(name: nil, hp: nil, setNumber: nil, illustrator: nil, centerSearchHint: nil)
        }

        let setNumber = extractSetNumber(from: lines)
        let hp = extractHP(from: lines)
        let name = extractName(from: lines)
        let illustrator = extractIllustrator(from: lines)
        let centerSearchHint = extractCenterSearchHint(from: lines)

        return ExtractedFields(name: name, hp: hp, setNumber: setNumber, illustrator: illustrator, centerSearchHint: centerSearchHint)
    }

    /// Reading order for debug: top → bottom, then left → right.
    static func sortedLinesForDebug(from observations: [VNRecognizedTextObservation]) -> [String] {
        observations
            .sorted { a, b in
                let dy = a.boundingBox.midY - b.boundingBox.midY
                if abs(dy) > 0.015 { return dy > 0 }
                return a.boundingBox.midX < b.boundingBox.midX
            }
            .compactMap { obs in
                obs.topCandidates(1).first.map(\.string)
            }
    }

    // MARK: - Line model

    private struct OCRLine {
        let text: String
        let boundingBox: CGRect

        var midX: CGFloat { boundingBox.midX }
        var midY: CGFloat { boundingBox.midY }
        /// Larger = bigger type (title often wins).
        var area: CGFloat { boundingBox.width * boundingBox.height }
    }

    // MARK: - Set number

    private static func extractSetNumber(from lines: [OCRLine]) -> String? {
        var candidates: [(value: String, midY: CGFloat)] = []
        for line in lines {
            let ns = line.text as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let m = setNumberRegex.firstMatch(in: line.text, range: range),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: line.text) {
                let value = String(line.text[r])
                candidates.append((value, line.midY))
            }
        }
        guard !candidates.isEmpty else { return nil }
        // Prefer the hit drawn nearest the **bottom** of the card (smallest midY).
        candidates.sort { $0.midY < $1.midY }
        return candidates.first?.value
    }

    // MARK: - HP

    private static func extractHP(from lines: [OCRLine]) -> String? {
        var scored: [(hp: String, score: CGFloat)] = []

        for line in lines {
            let trimmedLine = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = trimmedLine as NSString
            let range = NSRange(location: 0, length: ns.length)

            var value: String?
            if let m = hpLeadingRegex.firstMatch(in: trimmedLine, range: range), m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: trimmedLine) {
                value = String(trimmedLine[r])
            } else if let m = hpTrailingRegex.firstMatch(in: trimmedLine, range: range), m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: trimmedLine) {
                value = String(trimmedLine[r])
            } else if let m = hpDotLeadingRegex.firstMatch(in: trimmedLine, range: range), m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: trimmedLine) {
                value = String(trimmedLine[r])
            } else if let m = hpMinusLeadingRegex.firstMatch(in: trimmedLine, range: range), m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: trimmedLine) {
                value = String(trimmedLine[r])
            }

            guard let hp = value, let intHp = Int(hp), (30...400).contains(intHp) else { continue }

            // Prefer top band + right side (classic Pokémon layout).
            let inTop = line.midY >= topBandMinY
            let inRight = line.midX >= hpRightMinX
            var score = line.midY * 1.2 + line.midX
            if inTop { score += 0.5 }
            if inRight { score += 0.35 }
            scored.append((hp, score))
        }

        return scored.max(by: { $0.score < $1.score })?.hp
    }

    // MARK: - Name

    private static func extractName(from lines: [OCRLine]) -> String? {
        let candidates = lines.filter { line in
            guard line.text.count >= 3 else { return false }

            let lower = line.text.lowercased()
            if noiseExactNames.contains(lower) { return false }
            if lower.hasPrefix("stage") { return false }

            let ns = line.text as NSString
            let rAll = NSRange(location: 0, length: ns.length)
            if skipLineRegex.firstMatch(in: line.text, range: rAll) != nil { return false }
            if setNumberRegex.firstMatch(in: line.text, range: rAll) != nil { return false }

            // Same line sometimes includes "HP …" — strip mentally by skipping pure-HP lines.
            if hpLeadingRegex.firstMatch(in: line.text, range: rAll) != nil { return false }
            if hpTrailingRegex.firstMatch(in: line.text, range: rAll) != nil { return false }

            // Title row: upper portion of the frame; name is usually left-ish.
            guard line.midY >= topBandMinY else { return false }
            guard line.midX <= nameLeftMaxX + 0.12 else { return false }

            return true
        }

        guard !candidates.isEmpty else {
            // Fallback: any top-band line that survived noise filters (e.g. odd layouts).
            let loose = lines.filter { line in
                guard line.text.count >= 3 else { return false }
                let lower = line.text.lowercased()
                if noiseExactNames.contains(lower) { return false }
                let ns = line.text as NSString
                let rAll = NSRange(location: 0, length: ns.length)
                if setNumberRegex.firstMatch(in: line.text, range: rAll) != nil { return false }
                if skipLineRegex.firstMatch(in: line.text, range: rAll) != nil { return false }
                return line.midY >= topBandMinY - 0.08
            }
            return pickBestNameLine(from: loose)
        }

        return pickBestNameLine(from: candidates)
    }

    // MARK: - Center (Pokémon attacks / Trainer rules)

    /// Collects text from the middle of the frame for catalog matching (`Card.attacks` or long `Card.rules`).
    private static func extractCenterSearchHint(from lines: [OCRLine]) -> String? {
        let center = lines.filter { line in
            line.midY >= centerBandMinY && line.midY <= centerBandMaxY
        }
        guard !center.isEmpty else { return nil }

        let scored: [(text: String, midY: CGFloat, area: CGFloat)] = center.compactMap { line in
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 3 else { return nil }
            let ns = t as NSString
            let rAll = NSRange(location: 0, length: ns.length)
            if centerBandNoiseRegex.firstMatch(in: t, range: rAll) != nil { return nil }
            if setNumberRegex.firstMatch(in: t, range: rAll) != nil { return nil }
            let lower = t.lowercased()
            if noiseExactNames.contains(lower) { return nil }
            if lineLooksLikeScriptNoise(t) { return nil }
            // Prefer lines that look like words (attack names / rules), not pure retreat pips.
            guard t.rangeOfCharacter(from: .letters) != nil || t.contains("+") else { return nil }
            return (t, line.midY, line.area)
        }
        guard !scored.isEmpty else { return nil }

        // Reading order: higher on the physical card first (larger Vision `midY`), then left.
        let sorted = scored.sorted { a, b in
            if abs(a.midY - b.midY) > 0.02 { return a.midY > b.midY }
            return a.text < b.text
        }

        var parts: [String] = []
        var used = Set<String>()
        for item in sorted.prefix(14) {
            let key = item.text.lowercased()
            guard !used.contains(key) else { continue }
            used.insert(key)
            parts.append(item.text)
            let joined = parts.joined(separator: " ")
            if joined.count > 320 { break }
        }
        var hint = parts.joined(separator: " ")
        hint = filterSearchNoise(hint) ?? ""
        return hint.isEmpty ? nil : hint
    }

    // MARK: - Illustrator

    private static func extractIllustrator(from lines: [OCRLine]) -> String? {
        let footer = lines.sorted { $0.midY < $1.midY }

        for (index, line) in footer.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let ns = text as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let match = illustratorInlineRegex.firstMatch(in: text, range: full),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: text) {
                return cleanIllustrator(String(text[range]))
            }

            let lower = text.lowercased()
            guard lower == "illus." || lower == "illus" || lower == "illustrator" else { continue }

            if let next = footer[safe: index + 1] {
                let candidate = cleanIllustrator(next.text)
                if candidate != nil { return candidate }
            }
        }

        return nil
    }

    private static func cleanIllustrator(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: #"^[\.\-: ]+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard t.count >= 3 else { return nil }
        guard t.rangeOfCharacter(from: .letters) != nil else { return nil }
        if setNumberRegex.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil {
            return nil
        }
        return t
    }

    /// Drops lines that are mostly non–basic-Latin letters (e.g. Cyrillic mixed into English OCR).
    private static func lineLooksLikeScriptNoise(_ s: String) -> Bool {
        let letters = s.filter(\.isLetter)
        guard letters.count >= 2 else { return false }
        let basicLatin = letters.filter { ch in
            guard let u = ch.unicodeScalars.first?.value else { return false }
            return (u >= 65 && u <= 90) || (u >= 97 && u <= 122)
        }
        return Double(basicLatin.count) / Double(letters.count) < 0.72
    }

    /// Prefer highest on card (max midY), then leftmost, then largest glyph area (title font).
    private static func pickBestNameLine(from lines: [OCRLine]) -> String? {
        let sorted = lines.sorted { a, b in
            if abs(a.midY - b.midY) > 0.02 { return a.midY > b.midY }
            if abs(a.midX - b.midX) > 0.02 { return a.midX < b.midX }
            return a.area > b.area
        }
        return sorted.first?.text
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
