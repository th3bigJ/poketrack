import AVFoundation
import UIKit
import Vision
import SwiftUI

enum ScanState {
    case idle
    case scanning
    case found(Card)
}

struct ScanDebugInfo {
    /// OCR lines in approximate reading order (top→bottom, left→right) for debugging only.
    var rawOCRStrings: [String] = []
    /// What the pipeline **read** and how it’s **used** (search vs rank) — for debugging OCR vs logic.
    var determinedOutline: String = ""
    var extractedName: String? = nil
    var extractedHP: String? = nil
    var extractedSetNumber: String? = nil
    /// Middle-of-card text folded into the catalog query (attacks / rules).
    var extractedCenterHint: String? = nil
    /// Human-readable **interpretation** of OCR (name, HP, #, center) after noise handling.
    var matchedSummary: String? = nil
    /// Exact string passed to catalog **search** for the winning tier (strict + soft).
    var searchQueryUsed: String? = nil
    /// `NN/NNN` strings mined from **all** raw OCR lines (ranking picks the best match per card).
    var minedCardNumbers: String? = nil
    /// Which narrow query tier succeeded first (e.g. `name+hp+center`).
    var narrowTier: String? = nil
    var searchResultCount: Int = 0
    var topResult: String? = nil
    var captureCount: Int = 0
    var matchBufferState: String = ""
}

@Observable
final class CardScannerViewModel: NSObject {
    // MARK: - Public state (read by view)
    var session = AVCaptureSession()
    var scanState: ScanState = .idle
    var detectedText: String? = nil
    var debugInfo = ScanDebugInfo()
    /// Frozen frame from the last capture; when non-nil the UI shows this instead of live preview.
    var capturedImage: UIImage?
    /// True while the shutter pipeline is finishing (before `capturedImage` is set).
    var isCapturing = false
    /// Set after the first successful `AVCaptureSession` configuration + `startRunning()` so SwiftUI can enable the shutter (KVO on `session.isRunning` is not enough for `@Observable`).
    var isCameraReady = false
    /// Last capture or OCR failure — surfaced so the user can retake.
    var lastErrorMessage: String?
    /// Results from the last successful catalog search (primary query). User picks one to open.
    var searchResults: [Card] = []
    /// When the primary query returned nothing, broader fallbacks (name-only, number correction, etc.).
    var alternativeMatches: [Card] = []

    // MARK: - Callbacks
    var onMatch: ((Card) -> Void)?

    // MARK: - Private
    private var cardDataService: CardDataService?
    private let photoOutput = AVCapturePhotoOutput()
    private var didConfigureSession = false
    private var matchBuffer: [String: Int] = [:]
    private let matchThreshold = 1
    private let maxMatchesToShow = 15

    // MARK: - Setup

    func configure(cardDataService: CardDataService) {
        self.cardDataService = cardDataService
    }

    /// Call when the user confirms which card to open (never auto-fired from search).
    func confirmOpenCard(_ card: Card) {
        onMatch?(card)
    }

    func startSession() {
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.setupCaptureSession()
        }
    }

    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    /// Clears the frozen frame and restarts live preview for another attempt.
    func retake() {
        capturedImage = nil
        lastErrorMessage = nil
        searchResults = []
        alternativeMatches = []
        scanState = .idle
        detectedText = nil
        matchBuffer.removeAll()
        debugInfo = ScanDebugInfo()
        Task { @MainActor in
            guard didConfigureSession else {
                startSession()
                return
            }
            if !session.isRunning {
                session.startRunning()
            }
            isCameraReady = true
        }
    }

    /// Fires the still photo pipeline; OCR runs when `photoOutput(_:didFinishProcessingPhoto:…)` delivers pixels.
    func capturePhoto() {
        guard session.isRunning, !isCapturing else { return }
        lastErrorMessage = nil
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCaptureSession setup

    private func setupCaptureSession() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                await MainActor.run { isCameraReady = false }
                return
            }
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            await MainActor.run { isCameraReady = false }
            return
        }

        if didConfigureSession {
            await MainActor.run {
                if !session.isRunning {
                    session.startRunning()
                }
                isCameraReady = true
            }
            return
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            await MainActor.run { isCameraReady = false }
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        if session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        didConfigureSession = true
        await MainActor.run {
            session.startRunning()
            isCameraReady = true
        }
    }

    // MARK: - Still image → Vision

    private func processStillImage(_ image: UIImage) {
        scanState = .scanning
        debugInfo.captureCount += 1

        guard let cgImage = image.normalizedCGImage() else {
            DispatchQueue.main.async { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "Could not read this photo. Try again."
            }
            return
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let request = VNRecognizeTextRequest { [weak self] req, error in
            if let error {
                print("[Scanner] OCR error: \(error)")
            }
            self?.handleTextObservations(req.results as? [VNRecognizedTextObservation] ?? [])
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("[Scanner] VNImageRequestHandler error: \(error)")
                DispatchQueue.main.async { [weak self] in
                    self?.scanState = .idle
                    self?.lastErrorMessage = "Text recognition failed. Try better light or retake."
                }
            }
        }
    }

    // MARK: - OCR result parsing

    private func handleTextObservations(_ observations: [VNRecognizedTextObservation]) {
        let sortedDebug = CardOCRFieldExtractor.sortedLinesForDebug(from: observations)
        let fields = CardOCRFieldExtractor.extract(from: observations)

        let mergedNumsPreview = ScannerCompositeRanker.mergedNumberCandidates(
            primary: fields.setNumber,
            extras: CardOCRFieldExtractor.extractCardNumberCandidates(from: sortedDebug)
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            debugInfo.rawOCRStrings = sortedDebug
            debugInfo.minedCardNumbers = mergedNumsPreview.isEmpty ? nil : mergedNumsPreview.joined(separator: ", ")
        }

        guard !sortedDebug.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.detectedText = nil
                self?.scanState = .idle
                self?.lastErrorMessage = "No text found. Try more light or a closer shot."
            }
            return
        }

        let cardName = fields.name
        let setNumber = fields.setNumber
        let centerHint = fields.centerSearchHint

        let hasNarrowSignal = [
            cardName.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
            fields.hp.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
            centerHint.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
        ].contains(true)

        guard hasNarrowSignal else {
            DispatchQueue.main.async { [weak self] in
                self?.detectedText = nil
                self?.scanState = .idle
                self?.lastErrorMessage = "Could not read card name, HP, or attack text. Try again."
                self?.debugInfo.extractedName = nil
                self?.debugInfo.extractedHP = nil
                self?.debugInfo.extractedSetNumber = nil
                self?.debugInfo.extractedCenterHint = nil
                self?.debugInfo.matchedSummary = nil
                self?.debugInfo.searchQueryUsed = nil
                self?.debugInfo.minedCardNumbers = nil
                self?.debugInfo.determinedOutline = ""
                self?.debugInfo.narrowTier = nil
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var summary = [cardName, setNumber].compactMap { $0 }.joined(separator: " ")
            if let hp = fields.hp {
                summary += summary.isEmpty ? "HP \(hp)" : " · HP \(hp)"
            }
            if let hint = centerHint, !hint.isEmpty {
                summary += summary.isEmpty ? hint : " · \(hint)"
            }
            detectedText = summary
            scanState = .scanning
            debugInfo.extractedName = cardName
            debugInfo.extractedHP = fields.hp
            debugInfo.extractedSetNumber = setNumber
            debugInfo.extractedCenterHint = centerHint
            debugInfo.matchedSummary = Self.matchedSummaryLine(
                name: cardName,
                hp: fields.hp,
                setNumber: setNumber,
                center: centerHint
            )
            debugInfo.determinedOutline = Self.determinedOutlineBlock(
                name: cardName,
                hp: fields.hp,
                setNumber: setNumber,
                centerHint: centerHint,
                minedCardNumbers: mergedNumsPreview
            )
        }

        let numberCandidates = CardOCRFieldExtractor.extractCardNumberCandidates(from: sortedDebug)
        let rawBlob = sortedDebug.joined(separator: "\n")

        Task { [weak self] in
            await self?.runSearch(
                cardName: cardName,
                hp: fields.hp,
                setNumber: setNumber,
                centerHint: centerHint,
                numberCandidates: numberCandidates,
                rawOCRBlob: rawBlob
            )
        }
    }

    private static func matchedSummaryLine(name: String?, hp: String?, setNumber: String?, center: String?) -> String {
        var parts: [String] = []
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            parts.append("name: \(n)")
        }
        if let h = hp?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            parts.append("HP: \(h)")
        }
        if let s = setNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            parts.append("#: \(s)")
        }
        if let c = center?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            let short = c.count > 180 ? String(c.prefix(180)) + "…" : c
            parts.append("center: \(short)")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " | ")
    }

    /// Plain-text block for the ladybug panel: what we **determined** from OCR and whether it feeds **search**, **rank**, or both.
    private static func determinedOutlineBlock(
        name: String?,
        hp: String?,
        setNumber: String?,
        centerHint: String?,
        minedCardNumbers: [String]
    ) -> String {
        let nameLine = displayOrDash(name)
        let hpLine = displayOrDash(hp)
        let primaryLine = displayOrDash(setNumber)
        let minedLine: String = {
            guard !minedCardNumbers.isEmpty else { return "— (none)" }
            return minedCardNumbers.joined(separator: ", ")
        }()
        let centerLine: String = {
            let c = displayOrDash(centerHint)
            guard c != "— (not read)" else { return c }
            if c.count > 220 { return String(c.prefix(220)) + "…" }
            return c
        }()

        return """
        READ → USE
        • Name: \(nameLine)
          → catalog SEARCH (tier queries: name+hp+center, …).
        • HP: \(hpLine)
          → catalog SEARCH only (not used in attack/rank score).
        • Card # (primary): \(primaryLine)
          → RANK vs JSON cardNumber (+ mined variants below).
        • Card # (mined from all OCR lines): \(minedLine)
          → RANK — best match per catalog row across these strings.
        • Center text (attacks / trainer rules): \(centerLine)
          → SEARCH + RANK vs JSON attacks[].name (Pokémon) or rules (Trainers).
        """
    }

    private static func displayOrDash(_ s: String?) -> String {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return "— (not read)" }
        return t
    }

    /// 1) Narrow with name + HP + center text. 2) Rank by combined score: capped attack overlap + best # match (mined from all OCR) + optional ex hint.
    private func runSearch(
        cardName: String?,
        hp: String?,
        setNumber: String?,
        centerHint: String?,
        numberCandidates: [String],
        rawOCRBlob: String?
    ) async {
        guard let service = cardDataService else {
            print("[Scanner] cardDataService is nil — was configure() called?")
            return
        }

        let narrowOutcome = await narrowSearchWithTiers(
            service: service,
            cardName: cardName,
            hp: hp,
            centerHint: centerHint
        )

        let ranked: [Card]
        let tierLabel: String?
        let usedQuery: String?

        if let (label, query, candidates) = narrowOutcome {
            tierLabel = label
            usedQuery = query
            ranked = ScannerCompositeRanker.rank(
                candidates,
                ocrCenterHint: centerHint,
                primaryCardNumber: setNumber,
                extraNumberCandidates: numberCandidates,
                rawOCRBlob: rawOCRBlob
            )
        } else {
            tierLabel = nil
            usedQuery = nil
            let alt = await fallbackMatches(
                service: service,
                cardName: cardName,
                setNumber: setNumber,
                centerHint: centerHint
            )
            ranked = ScannerCompositeRanker.rank(
                alt,
                ocrCenterHint: centerHint,
                primaryCardNumber: setNumber,
                extraNumberCandidates: numberCandidates,
                rawOCRBlob: rawOCRBlob
            )
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            debugInfo.narrowTier = tierLabel
            debugInfo.searchQueryUsed = usedQuery ?? (ranked.isEmpty ? nil : "fallback queries")
            debugInfo.searchResultCount = ranked.count
            debugInfo.topResult = ranked.first.map { "\($0.cardName) [\($0.setCode) \($0.cardNumber)]" }
        }

        guard let top = ranked.first else {
            await MainActor.run { [weak self] in
                guard let self else { return }
                matchBuffer.removeAll()
                searchResults = []
                alternativeMatches = []
                debugInfo.matchBufferState = "no candidates"
                scanState = .idle
                lastErrorMessage = "No catalog match for that text. Try Retake."
            }
            return
        }

        let ocrCenterNorm = centerHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let mergedNums = ScannerCompositeRanker.mergedNumberCandidates(primary: setNumber, extras: numberCandidates)
        let topBreakdown = ScannerCompositeRanker.scoreBreakdown(
            card: top,
            ocrCenter: ocrCenterNorm,
            numberCandidates: mergedNums,
            rawOCRBlob: rawOCRBlob
        )
        await MainActor.run { [weak self] in
            guard let self else { return }
            let count = (matchBuffer[top.masterCardId] ?? 0) + 1
            matchBuffer = [top.masterCardId: count]
            let tier = tierLabel ?? "fallback"
            debugInfo.matchBufferState = "\(tier) → \(ranked.count) · total \(topBreakdown.total) (atk \(topBreakdown.cappedAttack) + #\(topBreakdown.number) + ex \(topBreakdown.ex)) · \(top.setCode) #\(top.cardNumber)"

            if count >= matchThreshold {
                searchResults = Array(ranked.prefix(maxMatchesToShow))
                alternativeMatches = []
                scanState = .found(top)
                matchBuffer.removeAll()
                lastErrorMessage = nil
            }
        }
    }

    /// Tries **name + HP + center** (attacks or trainer **rules**) first, then relaxes. Collector number is ranked separately.
    /// Center text uses strict token search first, then **soft** partial token overlap so long `rules` can match noisy OCR.
    private func narrowSearchWithTiers(
        service: CardDataService,
        cardName: String?,
        hp: String?,
        centerHint: String?
    ) async -> (tier: String, query: String, cards: [Card])? {
        let hasName = !(cardName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasHp = !(hp?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasCenter = !(centerHint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        var tiers: [(String, String)] = []
        if hasName, hasHp, hasCenter {
            tiers.append(("name+hp+center", joinSearchParts(cardName, hp, centerHint)))
        }
        if hasName, hasCenter {
            tiers.append(("name+center", joinSearchParts(cardName, centerHint)))
        }
        if hasName, hasHp {
            tiers.append(("name+hp", joinSearchParts(cardName, hp)))
        }
        if hasName {
            tiers.append(("name", joinSearchParts(cardName)))
        }
        if !hasName, hasHp, hasCenter {
            tiers.append(("hp+center", joinSearchParts(hp, centerHint)))
        }
        if !hasName, hasHp {
            tiers.append(("hp", joinSearchParts(hp)))
        }
        if hasCenter {
            tiers.append(("center", joinSearchParts(centerHint)))
        }

        for (label, raw) in tiers {
            let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { continue }
            let r = await tierSearch(service: service, query: q)
            if !r.isEmpty {
                return (label, q, r)
            }
        }
        return nil
    }

    /// Strict inverted-index search, then **soft** partial token match (trainer rules / long center OCR).
    private func tierSearch(service: CardDataService, query: String) async -> [Card] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let strict = await service.search(query: trimmed)
        if !strict.isEmpty { return strict }
        return await service.searchSoftTokenMatch(query: trimmed)
    }

    private func joinSearchParts(_ parts: String?...) -> String {
        parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { fragment -> String? in
                let cleaned = CardOCRFieldExtractor.filterSearchNoise(fragment) ?? fragment
                let t = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            .joined(separator: " ")
    }

    /// Broader searches when no tier matched (OCR typos). May include **card number** variants; results are still **ranked** by number elsewhere.
    private func fallbackMatches(
        service: CardDataService,
        cardName: String?,
        setNumber: String?,
        centerHint: String?
    ) async -> [Card] {
        var queries: [String] = []
        if let name = cardName, !name.isEmpty { queries.append(name) }
        if let hint = centerHint, !hint.isEmpty {
            queries.append(hint)
            let firstToken = hint.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            if firstToken.count >= 4 { queries.append(firstToken) }
        }
        if let sn = setNumber, !sn.isEmpty {
            queries.append(sn)
            for variant in setNumberVariants(sn) {
                queries.append(variant)
                if let name = cardName, !name.isEmpty {
                    queries.append("\(name) \(variant)")
                }
            }
        }

        var seen = Set<String>()
        var out: [Card] = []
        for q in queries {
            let r = await tierSearch(service: service, query: q)
            for c in r {
                if seen.insert(c.masterCardId).inserted {
                    out.append(c)
                    if out.count >= maxMatchesToShow { return out }
                }
            }
        }
        return out
    }

    private func setNumberVariants(_ sn: String) -> [String] {
        let parts = sn.split(separator: "/")
        guard parts.count == 2 else { return [] }
        let left = String(parts[0])
        let right = String(parts[1])
        var v: [String] = []
        // Common OCR: leading 1 instead of 0 (162/193 → 062/193)
        if left.count == 3, left.first == "1", left.dropFirst().allSatisfy({ $0.isNumber }) {
            let trimmed = String(left.dropFirst())
            if trimmed.count == 2 {
                v.append("0\(trimmed)/\(right)")
                v.append("\(trimmed)/\(right)")
            }
        }
        if left.count == 2, Int(left) != nil {
            v.append("0\(left)/\(right)")
        }
        return v
    }
}

// MARK: - Composite ranking (attacks + mined # + HP + ex hint)

/// Combines **capped** attack/rules overlap, the **best** card-number match across all OCR fractions, **HP** alignment, and optional **ex** name hint so one signal cannot drown out the others.
private enum ScannerCompositeRanker {
    /// Keeps wrong printings from winning on attack tokens alone when the real `068/167` appears elsewhere in the OCR blob.
    private static let attackContributionCap = 380_000

    struct ScoreBreakdown {
        let total: Int
        let cappedAttack: Int
        let number: Int
        let ex: Int
    }

    static func mergedNumberCandidates(primary: String?, extras: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        if let p = primary?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            seen.insert(p)
            out.append(p)
        }
        for e in extras {
            let t = e.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }

    static func rank(
        _ cards: [Card],
        ocrCenterHint: String?,
        primaryCardNumber: String?,
        extraNumberCandidates: [String],
        rawOCRBlob: String?
    ) -> [Card] {
        let ocrCenter = ocrCenterHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let merged = mergedNumberCandidates(primary: primaryCardNumber, extras: extraNumberCandidates)
        return cards.sorted { a, b in
            let ta = totalRankScore(
                card: a,
                ocrCenter: ocrCenter,
                numberCandidates: merged,
                rawOCRBlob: rawOCRBlob
            )
            let tb = totalRankScore(
                card: b,
                ocrCenter: ocrCenter,
                numberCandidates: merged,
                rawOCRBlob: rawOCRBlob
            )
            if ta != tb { return ta > tb }
            return a.masterCardId < b.masterCardId
        }
    }

    static func scoreBreakdown(
        card: Card,
        ocrCenter: String,
        numberCandidates: [String],
        rawOCRBlob: String?
    ) -> ScoreBreakdown {
        let rawAttack = centerTextScore(ocrCenter: ocrCenter, card: card)
        let capped = min(rawAttack, attackContributionCap)
        let num = bestNumberScore(card: card, candidates: numberCandidates)
        let x = exNameConsistencyScore(ocrBlob: rawOCRBlob, card: card)
        return ScoreBreakdown(
            total: capped + num + x,
            cappedAttack: capped,
            number: num,
            ex: x
        )
    }

    private static func totalRankScore(
        card: Card,
        ocrCenter: String,
        numberCandidates: [String],
        rawOCRBlob: String?
    ) -> Int {
        scoreBreakdown(card: card, ocrCenter: ocrCenter, numberCandidates: numberCandidates, rawOCRBlob: rawOCRBlob).total
    }

    private static func bestNumberScore(card: Card, candidates: [String]) -> Int {
        var best = 0
        for c in candidates {
            let s = ScannerCardNumberRanker.score(ocr: c, catalog: card.cardNumber)
            if s > best { best = s }
        }
        return best
    }

    /// Small boost when both the catalog name and the raw OCR mention **ex** (Pokémon ex rule box / title).
    private static func exNameConsistencyScore(ocrBlob: String?, card: Card) -> Int {
        let blob = ocrBlob?.lowercased() ?? ""
        let cn = card.cardName.lowercased()
        let cardMentionsEx = cn.contains(" ex")
        let ocrMentionsEx = blob.contains(" ex") || (blob.range(of: #"\bex\b"#, options: .regularExpression) != nil)
        if cardMentionsEx && ocrMentionsEx { return 150_000 }
        return 0
    }

    static func centerTextScore(ocrCenter: String, card: Card) -> Int {
        guard !ocrCenter.isEmpty else { return 0 }
        if let attacks = card.attacks, !attacks.isEmpty {
            return pokemonAttackOverlapScore(ocrCenter: ocrCenter, attacks: attacks)
        }
        if let rules = card.rules, !rules.isEmpty {
            return trainerRulesOverlapScore(ocrCenter: ocrCenter, rules: rules)
        }
        return 0
    }

    /// Uses **distinctive** tokens from printed attack names only (not descriptions). Rewards **recall** of those tokens in OCR; weak single-token hits no longer add large fake scores.
    private static func pokemonAttackOverlapScore(ocrCenter: String, attacks: [CardAttack]) -> Int {
        var catalogTokens = Set<String>()
        for a in attacks {
            for t in distinctiveAttackTokens(a.name.lowercased()) {
                catalogTokens.insert(t)
            }
        }
        guard !catalogTokens.isEmpty else { return 0 }

        let ocrTokens = distinctiveAttackTokens(ocrCenter)
        guard !ocrTokens.isEmpty else { return 0 }

        let inter = catalogTokens.intersection(ocrTokens)
        if inter.isEmpty { return 0 }

        // Primary: fraction of catalog **attack-name** tokens found in OCR (wrong printings usually share none).
        let recall = Double(inter.count) / Double(catalogTokens.count)
        var score = Int(recall * 450_000)

        // Secondary: Jaccard dampens when OCR is full of unrelated words.
        let union = catalogTokens.union(ocrTokens)
        let jaccard = Double(inter.count) / Double(max(union.count, 1))
        score += Int(jaccard * 120_000)

        // Per-attack: need a **strong** match on each name (≥2 tokens or one long token), not a single 3-letter hit.
        for a in attacks {
            let nameToks = distinctiveAttackTokens(a.name.lowercased())
            guard nameToks.count >= 1 else { continue }
            let hit = nameToks.intersection(ocrTokens)
            let longHit = hit.contains { $0.count >= 6 }
            let ratio = Double(hit.count) / Double(nameToks.count)
            if longHit || hit.count >= 2 || (nameToks.count == 1 && ratio >= 1) || (nameToks.count == 2 && hit.count >= 1 && ratio >= 0.5) {
                score += 35_000
            }
        }

        return score
    }

    private static func trainerRulesOverlapScore(ocrCenter: String, rules: String) -> Int {
        let cTokens = significantTokens(rules.lowercased())
        let oTokens = significantTokens(ocrCenter)
        guard !cTokens.isEmpty, !oTokens.isEmpty else { return 0 }
        let inter = cTokens.intersection(oTokens)
        return inter.count * 80_000 + (inter.count * 40_000) / max(cTokens.count, 1)
    }

    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "for", "to", "of", "in", "on", "at", "as", "is", "it", "if", "then",
        "your", "you", "up", "any", "can", "may", "be", "with", "from", "that", "this", "into", "are",
    ]

    /// Extra words that appear in **rules text** OCR and many cards — must not drive “attack match”.
    private static let attackNoiseStopwords: Set<String> = [
        "damage", "energy", "discard", "deck", "bench", "hand", "opponent", "prize", "attack", "attacks",
        "pokemon", "pokémon", "basic", "card", "cards", "this", "each", "all", "two", "one", "three",
        "your", "you", "then", "when", "take", "takes", "put", "flip", "coin", "search", "shuffle", "turn",
        "before", "during", "after", "knocked", "knock", "out", "prizes", "draw", "reveal", "choose",
        "special", "item", "supporter", "stadium", "tool", "stage", "evolves", "from", "has", "have",
    ]

    private static func significantTokens(_ text: String) -> Set<String> {
        let raw = SearchTokenizer.tokens(from: text)
        var s = Set<String>()
        for t in raw {
            guard t.count >= 3 else { continue }
            if stopwords.contains(t) { continue }
            s.insert(t)
        }
        return s
    }

    /// Stricter tokens for **attack name** ↔ OCR matching (longer words, fewer generic TCG terms).
    private static func distinctiveAttackTokens(_ text: String) -> Set<String> {
        let raw = SearchTokenizer.tokens(from: text.lowercased())
        var s = Set<String>()
        let blocked = stopwords.union(attackNoiseStopwords)
        for t in raw {
            guard t.count >= 4 else { continue }
            if blocked.contains(t) { continue }
            s.insert(t)
        }
        return s
    }
}

// MARK: - Card number ranking (partial OCR)

/// Tie-breaker after center-text match: best `cardNumber` vs noisy OCR.
private enum ScannerCardNumberRanker {
    static func rank(_ cards: [Card], ocrCardNumber: String?) -> [Card] {
        guard let ocr = ocrCardNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty else {
            return cards
        }
        return cards.sorted { a, b in
            let sa = score(ocr: ocr, catalog: a.cardNumber)
            let sb = score(ocr: ocr, catalog: b.cardNumber)
            if sa != sb { return sa > sb }
            return a.masterCardId < b.masterCardId
        }
    }

    static func score(ocr: String, catalog cardNumber: String) -> Int {
        let c = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let o = ocr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !o.isEmpty else { return 0 }

        if c == o { return 1_000_000 }

        let cParts = c.split(separator: "/").map(String.init)
        let oParts = o.split(separator: "/").map(String.init)

        guard cParts.count == 2 else {
            return (c.contains(o) || o.contains(c)) ? 50_000 : 0
        }

        let cLeft = cParts[0]
        let cRight = cParts[1]

        if oParts.count == 2 {
            let oLeft = oParts[0]
            let oRight = oParts[1]
            var score = 0
            if intEqual(cLeft, oLeft) { score += 500_000 }
            else if smallDigitStringClose(cLeft, oLeft) { score += 350_000 }
            if intEqual(cRight, oRight) { score += 400_000 }
            else if smallDigitStringClose(cRight, oRight) { score += 250_000 }
            return score
        }

        if oParts.count == 1 {
            let fragment = oParts[0]
            if intEqual(cLeft, fragment) { return 450_000 }
            if c.hasPrefix(fragment + "/") || c.hasPrefix(fragment) { return 380_000 }
        }

        return c.contains(o) ? 40_000 : 0
    }

    private static func intEqual(_ a: String, _ b: String) -> Bool {
        let ia = Int(a)
        let ib = Int(b)
        if let ia, let ib { return ia == ib }
        return a == b
    }

    /// One typical OCR slip on short numeric strings (e.g. `162` vs `062`).
    private static func smallDigitStringClose(_ a: String, _ b: String) -> Bool {
        guard a != b else { return true }
        guard a.allSatisfy(\.isNumber), b.allSatisfy(\.isNumber) else { return false }
        guard a.count <= 4, b.count <= 4 else { return false }
        if a.count == b.count {
            return zip(a, b).filter { $0 != $1 }.count <= 1
        }
        return editDistanceAtMostOne(a, b)
    }

    private static func editDistanceAtMostOne(_ a: String, _ b: String) -> Bool {
        let (s, t) = a.count <= b.count ? (a, b) : (b, a)
        guard t.count - s.count <= 1 else { return false }
        var i = s.startIndex
        var j = t.startIndex
        var skipped = 0
        while i < s.endIndex && j < t.endIndex {
            if s[i] == t[j] {
                i = s.index(after: i)
                j = t.index(after: j)
            } else {
                skipped += 1
                if skipped > 1 { return false }
                if s.count == t.count {
                    i = s.index(after: i)
                    j = t.index(after: j)
                } else {
                    j = t.index(after: j)
                }
            }
        }
        return skipped + s.distance(from: i, to: s.endIndex) + t.distance(from: j, to: t.endIndex) <= 1
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CardScannerViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                       didFinishProcessingPhoto photo: AVCapturePhoto,
                       error: Error?) {
        if let error {
            print("[Scanner] capture error: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isCapturing = false
                self?.lastErrorMessage = "Could not capture photo. Try again."
            }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.isCapturing = false
                self?.lastErrorMessage = "Could not read photo data. Try again."
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isCapturing = false
            capturedImage = image
            stopSession()
            processStillImage(image)
        }
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    /// Returns a CGImage suitable for Vision, applying `imageOrientation` into pixel data when needed.
    func normalizedCGImage() -> CGImage? {
        if let cg = cgImage {
            return cg
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
