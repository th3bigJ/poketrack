import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
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
    var extractedIllustrator: String? = nil
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

enum ScanReviewStep: Int, CaseIterable {
    case flattened
    case zones
    case extractedText
    case matchReview

    var title: String {
        switch self {
        case .flattened: return "Flattened card"
        case .zones: return "Scan zones"
        case .extractedText: return "Extracted text"
        case .matchReview: return "Match reasoning"
        }
    }
}

struct ScannerCandidateExplanation: Identifiable {
    let card: Card
    let totalScore: Int
    let attackScore: Int
    let numberScore: Int
    let artistScore: Int
    let exScore: Int

    var id: String { card.masterCardId }
}

struct CardQuad {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    var pathPoints: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
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
    /// Reticle-only crop from the captured frame.
    var croppedCardImage: UIImage?
    /// Crop after rectangle detection + perspective correction.
    var flattenedCardImage: UIImage?
    /// Best quad detected inside `croppedCardImage`, in image pixel coordinates.
    var detectedCardQuad: CardQuad?
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
    /// Ranked explanations shown in the step-by-step review.
    var candidateExplanations: [ScannerCandidateExplanation] = []
    var reviewStep: ScanReviewStep = .flattened

    // MARK: - Callbacks
    var onMatch: ((Card) -> Void)?

    // MARK: - Private
    private var cardDataService: CardDataService?
    private let photoOutput = AVCapturePhotoOutput()
    private var didConfigureSession = false
    /// Normalized rect (0–1) of the card frame within the screen, set by the reticle view before capture.
    /// Used to crop the full camera image down to just the card before running OCR.
    var cardNormalizedRect: CGRect = .zero
    private var matchBuffer: [String: Int] = [:]
    private let matchThreshold = 1
    private let maxMatchesToShow = 15
    private let ciContext = CIContext(options: nil)

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
        croppedCardImage = nil
        flattenedCardImage = nil
        detectedCardQuad = nil
        lastErrorMessage = nil
        searchResults = []
        alternativeMatches = []
        candidateExplanations = []
        reviewStep = .flattened
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

    func goToNextReviewStep() {
        guard let next = ScanReviewStep(rawValue: reviewStep.rawValue + 1) else { return }
        reviewStep = next
    }

    func goToPreviousReviewStep() {
        guard let previous = ScanReviewStep(rawValue: reviewStep.rawValue - 1) else { return }
        reviewStep = previous
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

        guard let fullCG = image.normalizedCGImage() else {
            DispatchQueue.main.async { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "Could not read this photo. Try again."
            }
            return
        }

        // Crop to just the card frame so OCR never sees text outside the reticle.
        let croppedCG = fullCG.croppedToCardRect(cardNormalizedRect, imageSize: image.size) ?? fullCG
        let croppedUIImage = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)

        DispatchQueue.main.async { [weak self] in
            self?.croppedCardImage = croppedUIImage
            self?.flattenedCardImage = croppedUIImage
            self?.detectedCardQuad = nil
            self?.reviewStep = .flattened
        }

        let ocrCGImage = preprocessCardForOCR(croppedCG) ?? croppedCG
        let ocrUIImage = UIImage(cgImage: ocrCGImage, scale: 1, orientation: .up)

        DispatchQueue.main.async { [weak self] in
            self?.flattenedCardImage = ocrUIImage
        }

        let orientation: CGImagePropertyOrientation = .up

        let request = VNRecognizeTextRequest { [weak self] req, error in
            if let error {
                print("[Scanner] OCR error: \(error)")
            }
            self?.handleTextObservations(req.results as? [VNRecognizedTextObservation] ?? [])
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: ocrCGImage, orientation: orientation, options: [:])
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

    private func preprocessCardForOCR(_ croppedCG: CGImage) -> CGImage? {
        let inputCI = CIImage(cgImage: croppedCG)
        guard let rectangle = detectCardRectangle(in: croppedCG) else {
            return croppedCG
        }

        let quad = rectangle.toCardQuad(imageWidth: croppedCG.width, imageHeight: croppedCG.height)
        DispatchQueue.main.async { [weak self] in
            self?.detectedCardQuad = quad
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = inputCI
        filter.topLeft = CGPoint(x: quad.topLeft.x, y: quad.topLeft.y)
        filter.topRight = CGPoint(x: quad.topRight.x, y: quad.topRight.y)
        filter.bottomLeft = CGPoint(x: quad.bottomLeft.x, y: quad.bottomLeft.y)
        filter.bottomRight = CGPoint(x: quad.bottomRight.x, y: quad.bottomRight.y)

        guard let output = filter.outputImage,
              let corrected = ciContext.createCGImage(output, from: output.extent.integral)
        else {
            return croppedCG
        }
        return corrected
    }

    private func detectCardRectangle(in image: CGImage) -> VNRectangleObservation? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 6
        request.minimumConfidence = 0.5
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.9
        request.quadratureTolerance = 18
        request.minimumSize = 0.35

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[Scanner] Rectangle detection error: \(error)")
            return nil
        }

        let observations = request.results ?? []
        guard !observations.isEmpty else { return nil }

        let expectedAspect = 63.0 / 88.0
        return observations.max { lhs, rhs in
            rectangleScore(lhs, expectedAspect: expectedAspect) < rectangleScore(rhs, expectedAspect: expectedAspect)
        }
    }

    private func rectangleScore(_ observation: VNRectangleObservation, expectedAspect: Double) -> Double {
        let widthTop = hypot(observation.topRight.x - observation.topLeft.x, observation.topRight.y - observation.topLeft.y)
        let widthBottom = hypot(observation.bottomRight.x - observation.bottomLeft.x, observation.bottomRight.y - observation.bottomLeft.y)
        let heightLeft = hypot(observation.topLeft.x - observation.bottomLeft.x, observation.topLeft.y - observation.bottomLeft.y)
        let heightRight = hypot(observation.topRight.x - observation.bottomRight.x, observation.topRight.y - observation.bottomRight.y)
        let avgWidth = (widthTop + widthBottom) / 2
        let avgHeight = (heightLeft + heightRight) / 2
        let aspect = avgWidth / max(avgHeight, 0.0001)
        let aspectPenalty = abs(aspect - expectedAspect) * 4
        let area = Double(observation.boundingBox.width * observation.boundingBox.height)
        return area - aspectPenalty
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
                self?.debugInfo.extractedIllustrator = nil
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
            debugInfo.extractedIllustrator = fields.illustrator
            debugInfo.extractedCenterHint = centerHint
            debugInfo.matchedSummary = Self.matchedSummaryLine(
                name: cardName,
                hp: fields.hp,
                setNumber: setNumber,
                illustrator: fields.illustrator,
                center: centerHint
            )
            debugInfo.determinedOutline = Self.determinedOutlineBlock(
                name: cardName,
                hp: fields.hp,
                setNumber: setNumber,
                illustrator: fields.illustrator,
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
                illustrator: fields.illustrator,
                centerHint: centerHint,
                numberCandidates: numberCandidates,
                rawOCRBlob: rawBlob
            )
        }
    }

    private static func matchedSummaryLine(name: String?, hp: String?, setNumber: String?, illustrator: String?, center: String?) -> String {
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
        if let i = illustrator?.trimmingCharacters(in: .whitespacesAndNewlines), !i.isEmpty {
            parts.append("illus: \(i)")
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
        illustrator: String?,
        centerHint: String?,
        minedCardNumbers: [String]
    ) -> String {
        let nameLine = displayOrDash(name)
        let hpLine = displayOrDash(hp)
        let primaryLine = displayOrDash(setNumber)
        let illustratorLine = displayOrDash(illustrator)
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
        • Illustrator: \(illustratorLine)
          → FILTER + RANK vs catalog artist when OCR catches the `Illus.` footer.
        • Center text (attacks / trainer rules): \(centerLine)
          → SEARCH + RANK vs JSON attacks[].name (Pokémon) or rules (Trainers).
        """
    }

    private static func displayOrDash(_ s: String?) -> String {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return "— (not read)" }
        return t
    }

    private static func cleanedOCRName(_ name: String?) -> String? {
        guard var t = name?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        t = t.replacingOccurrences(of: #"[|]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^[^A-Za-z]+|[^A-Za-z]+$"#, with: "", options: .regularExpression)
        let tokens = t.split(whereSeparator: \.isWhitespace).map(String.init)
        let cleanedTokens = tokens.filter { token in
            let letters = token.filter(\.isLetter)
            guard letters.count >= 2 else { return false }
            let ratio = Double(letters.count) / Double(max(token.count, 1))
            return ratio >= 0.55
        }
        let cleaned = cleanedTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func compactQuerySummary(
        cleanedName: String?,
        setNumber: String?,
        illustrator: String?,
        centerHint: String?
    ) -> String {
        var parts: [String] = []
        if let cleanedName, !cleanedName.isEmpty { parts.append("name=\(cleanedName)") }
        if let setNumber, !setNumber.isEmpty { parts.append("#=\(setNumber)") }
        if let illustrator, !illustrator.isEmpty { parts.append("artist=\(illustrator)") }
        if let centerHint, !centerHint.isEmpty {
            let short = centerHint.count > 80 ? String(centerHint.prefix(80)) + "…" : centerHint
            parts.append("center=\(short)")
        }
        return parts.joined(separator: " | ")
    }

    private func mixedFallbackPool(
        service: CardDataService,
        cleanedName: String?,
        setNumber: String?,
        illustrator: String?,
        centerHint: String?
    ) async -> [Card] {
        var combined: [Card] = []

        if let cleanedName, !cleanedName.isEmpty {
            combined.append(contentsOf: await service.searchByName(query: cleanedName))
            combined.append(contentsOf: await service.search(query: cleanedName))
        }
        if let setNumber, !setNumber.isEmpty {
            combined.append(contentsOf: await service.search(query: setNumber))
        }
        if let illustrator, !illustrator.isEmpty {
            combined.append(contentsOf: await service.search(query: illustrator))
        }
        if let centerHint, !centerHint.isEmpty {
            combined.append(contentsOf: await service.searchSoftTokenMatch(query: centerHint))
        }

        return Self.dedupCards(combined)
    }

    private static func dedupCards(_ cards: [Card]) -> [Card] {
        var seen = Set<String>()
        var out: [Card] = []
        for card in cards {
            if seen.insert(card.masterCardId).inserted {
                out.append(card)
            }
        }
        return out
    }

    /// Elimination pipeline:
    /// 1. Search by name only → all printings of the named card.
    /// 2. Filter by HP — only skipped for cards without HP (Trainers/Energy).
    /// 3. Rank survivors by card number match + attack/rules overlap.
    /// Fallback: if no name read, fall back to center-text search (Trainer/Energy no-name case).
    private func runSearch(
        cardName: String?,
        hp: String?,
        setNumber: String?,
        illustrator: String?,
        centerHint: String?,
        numberCandidates: [String],
        rawOCRBlob: String?
    ) async {
        guard let service = cardDataService else {
            print("[Scanner] cardDataService is nil — was configure() called?")
            return
        }

        let rawName = cardName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = Self.cleanedOCRName(rawName)
        let hasName = !(rawName?.isEmpty ?? true)
        let hasHp   = !(hp?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        // Step 1: candidate pool — name-only search so attacks/rules can never pull in wrong-name cards.
        var pool: [Card]
        var tierLabel: String
        var usedQuery: String
        if hasName {
            pool = await service.searchByName(query: rawName!)
            tierLabel = "name"
            usedQuery = rawName!
            if pool.isEmpty,
               let cleanedName,
               cleanedName.caseInsensitiveCompare(rawName!) != .orderedSame {
                pool = await service.searchByName(query: cleanedName)
                tierLabel = "name-clean"
                usedQuery = cleanedName
            }
            if pool.isEmpty, let cleanedName {
                pool = await service.search(query: cleanedName)
                if pool.isEmpty {
                    pool = await service.searchSoftTokenMatch(query: cleanedName)
                }
                if !pool.isEmpty {
                    tierLabel = "name-fuzzy"
                    usedQuery = cleanedName
                }
            }
        } else if let hint = centerHint, !hint.isEmpty {
            // No name read (e.g. Trainer/Energy) — fall back to center-text search.
            pool = await service.search(query: hint)
            if pool.isEmpty { pool = await service.searchSoftTokenMatch(query: hint) }
            tierLabel = "center-only"
            usedQuery = hint
        } else {
            pool = []
            tierLabel = "none"
            usedQuery = ""
        }

        if pool.isEmpty {
            pool = await mixedFallbackPool(
                service: service,
                cleanedName: cleanedName,
                setNumber: setNumber,
                illustrator: illustrator,
                centerHint: centerHint
            )
            if !pool.isEmpty {
                tierLabel = "fallback-mixed"
                usedQuery = Self.compactQuerySummary(
                    cleanedName: cleanedName,
                    setNumber: setNumber,
                    illustrator: illustrator,
                    centerHint: centerHint
                )
            }
        }

        // Step 2: HP filter — eliminates wrong-HP printings.
        // Cards without an HP field (Trainers/Energy) always pass through.
        if hasHp, let ocrHP = Int(hp!.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let hpFiltered = pool.filter { card in
                guard let cardHP = card.hp else { return true }  // no HP field → keep (Trainer/Energy)
                return cardHP == ocrHP
            }
            if !hpFiltered.isEmpty {
                pool = hpFiltered
                tierLabel += "+hp"
            }
            // If HP filter wiped everything (OCR misread HP), keep the pre-filter pool.
        }

        if let illustrator, !illustrator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let artistFiltered = pool.filter { card in
                ScannerCompositeRanker.artistScore(ocrIllustrator: illustrator, card: card) > 0
            }
            if !artistFiltered.isEmpty {
                pool = artistFiltered
                tierLabel += "+artist"
            }
        }

        // Step 3: rank survivors by card number + attack/rules overlap.
        let ranked = ScannerCompositeRanker.rank(
            pool,
            ocrCenterHint: centerHint,
            primaryCardNumber: setNumber,
            extraNumberCandidates: numberCandidates,
            ocrIllustrator: illustrator,
            rawOCRBlob: rawOCRBlob
        )

        let ocrCenterNorm = centerHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let mergedNums = ScannerCompositeRanker.mergedNumberCandidates(primary: setNumber, extras: numberCandidates)
        let explanations = Array(ranked.prefix(maxMatchesToShow)).map { card -> ScannerCandidateExplanation in
            let breakdown = ScannerCompositeRanker.scoreBreakdown(
                card: card,
                ocrCenter: ocrCenterNorm,
                numberCandidates: mergedNums,
                ocrIllustrator: illustrator,
                rawOCRBlob: rawOCRBlob
            )
            return ScannerCandidateExplanation(
                card: card,
                totalScore: breakdown.total,
                attackScore: breakdown.cappedAttack,
                numberScore: breakdown.number,
                artistScore: breakdown.artist,
                exScore: breakdown.ex
            )
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            debugInfo.narrowTier = tierLabel
            debugInfo.searchQueryUsed = usedQuery
            debugInfo.searchResultCount = ranked.count
            debugInfo.topResult = ranked.first.map { "\($0.cardName) [\($0.setCode) \($0.cardNumber)]" }
            candidateExplanations = explanations
        }

        guard let top = ranked.first else {
            await MainActor.run { [weak self] in
                guard let self else { return }
                matchBuffer.removeAll()
                searchResults = []
                alternativeMatches = []
                candidateExplanations = []
                debugInfo.matchBufferState = "no candidates"
                scanState = .idle
                lastErrorMessage = "No catalog match for that text. Try Retake."
            }
            return
        }

        let topBreakdown = ScannerCompositeRanker.scoreBreakdown(
            card: top,
            ocrCenter: ocrCenterNorm,
            numberCandidates: mergedNums,
            ocrIllustrator: illustrator,
            rawOCRBlob: rawOCRBlob
        )
        await MainActor.run { [weak self] in
            guard let self else { return }
            let count = (matchBuffer[top.masterCardId] ?? 0) + 1
            matchBuffer = [top.masterCardId: count]
            debugInfo.matchBufferState = "\(tierLabel) → \(ranked.count) · total \(topBreakdown.total) (atk \(topBreakdown.cappedAttack) + #\(topBreakdown.number) + ex \(topBreakdown.ex)) · \(top.setCode) #\(top.cardNumber)"

            if count >= matchThreshold {
                searchResults = Array(ranked.prefix(maxMatchesToShow))
                alternativeMatches = []
                scanState = .found(top)
                matchBuffer.removeAll()
                lastErrorMessage = nil
            }
        }
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
        let artist: Int
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
        ocrIllustrator: String? = nil,
        rawOCRBlob: String?
    ) -> [Card] {
        let ocrCenter = ocrCenterHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let merged = mergedNumberCandidates(primary: primaryCardNumber, extras: extraNumberCandidates)
        return cards.sorted { a, b in
            let ta = totalRankScore(
                card: a,
                ocrCenter: ocrCenter,
                numberCandidates: merged,
                ocrIllustrator: ocrIllustrator,
                rawOCRBlob: rawOCRBlob
            )
            let tb = totalRankScore(
                card: b,
                ocrCenter: ocrCenter,
                numberCandidates: merged,
                ocrIllustrator: ocrIllustrator,
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
        ocrIllustrator: String? = nil,
        rawOCRBlob: String?
    ) -> ScoreBreakdown {
        let rawAttack = centerTextScore(ocrCenter: ocrCenter, card: card)
        let capped = min(rawAttack, attackContributionCap)
        let num = bestNumberScore(card: card, candidates: numberCandidates)
        let artist = artistScore(ocrIllustrator: ocrIllustrator, card: card)
        let x = exNameConsistencyScore(ocrBlob: rawOCRBlob, card: card)
        return ScoreBreakdown(
            total: capped + num + artist + x,
            cappedAttack: capped,
            number: num,
            artist: artist,
            ex: x
        )
    }

    private static func totalRankScore(
        card: Card,
        ocrCenter: String,
        numberCandidates: [String],
        ocrIllustrator: String? = nil,
        rawOCRBlob: String?
    ) -> Int {
        scoreBreakdown(
            card: card,
            ocrCenter: ocrCenter,
            numberCandidates: numberCandidates,
            ocrIllustrator: ocrIllustrator,
            rawOCRBlob: rawOCRBlob
        ).total
    }

    private static func bestNumberScore(card: Card, candidates: [String]) -> Int {
        var best = 0
        for c in candidates {
            let s = ScannerCardNumberRanker.score(ocr: c, catalog: card.cardNumber)
            if s > best { best = s }
        }
        return best
    }

    static func artistScore(ocrIllustrator: String?, card: Card) -> Int {
        let ocr = significantTokens(ocrIllustrator?.lowercased() ?? "")
        let artist = significantTokens(card.artist?.lowercased() ?? "")
        guard !ocr.isEmpty, !artist.isEmpty else { return 0 }
        let inter = ocr.intersection(artist)
        guard !inter.isEmpty else { return 0 }
        if ocr == artist { return 260_000 }
        let recall = Double(inter.count) / Double(max(artist.count, 1))
        return Int(recall * 200_000)
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

private extension VNRectangleObservation {
    func toCardQuad(imageWidth: Int, imageHeight: Int) -> CardQuad {
        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)

        func denormalize(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * width, y: point.y * height)
        }

        return CardQuad(
            topLeft: denormalize(topLeft),
            topRight: denormalize(topRight),
            bottomLeft: denormalize(bottomLeft),
            bottomRight: denormalize(bottomRight)
        )
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
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

// MARK: - CGImage crop helpers

private extension CGImage {
    /// Crops a full-camera CGImage to the card reticle rect.
    ///
    /// The camera uses `.resizeAspectFill` so the image may be larger than the screen.
    /// `normalizedRect` is in screen-space (0–1 of screen width/height).
    /// We map it to the actual pixel rect, accounting for the fill scale.
    func croppedToCardRect(_ normalizedRect: CGRect, imageSize: CGSize) -> CGImage? {
        guard !normalizedRect.isEmpty else { return nil }

        let imgW = CGFloat(width)
        let imgH = CGFloat(height)

        // The camera fills the screen: compute scale factors for each axis.
        let scaleX = imgW / imageSize.width
        let scaleY = imgH / imageSize.height
        // AspectFill uses the larger scale so the smaller dimension is cropped symmetrically.
        let fillScale = max(scaleX, scaleY)

        // Offset of the image relative to the screen (the cropped-away half on each axis).
        let offsetX = (imgW - imageSize.width  * fillScale) / 2
        let offsetY = (imgH - imageSize.height * fillScale) / 2

        // Map normalised screen rect → pixel rect inside the full camera image.
        let cropX = offsetX + normalizedRect.minX * imageSize.width  * fillScale
        let cropY = offsetY + normalizedRect.minY * imageSize.height * fillScale
        let cropW = normalizedRect.width  * imageSize.width  * fillScale
        let cropH = normalizedRect.height * imageSize.height * fillScale

        let pixelRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
            .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

        guard !pixelRect.isEmpty else { return nil }
        return cropping(to: pixelRect)
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
