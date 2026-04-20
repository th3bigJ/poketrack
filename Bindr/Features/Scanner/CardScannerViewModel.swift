import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
@preconcurrency import Vision
import SwiftUI

enum ScanState {
    case idle
    case scanning
}

struct CardQuad {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    var pathPoints: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
}

/// A single completed scan — the matched catalog card (art loads from `Card.imageLowSrc` / `imageHighSrc`).
struct ScanResult: Identifiable {
    let id: UUID
    let card: Card
    /// Other ranked catalog matches for the same OCR pass (excludes `card`). User can pick one via “Wrong card?”.
    let alternativeCards: [Card]

    init(id: UUID = UUID(), card: Card, alternativeCards: [Card] = []) {
        self.id = id
        self.card = card
        self.alternativeCards = alternativeCards
    }
}

@Observable
final class CardScannerViewModel: NSObject, @unchecked Sendable {

    // MARK: - Public state

    var session = AVCaptureSession()
    var scanState: ScanState = .idle

    /// All completed scan results, newest first. Swiping the bar navigates this array.
    var scanResults: [ScanResult] = []

    /// True while the shutter pipeline is in flight.
    var isCapturing = false
    /// True after AVCaptureSession is configured and running.
    var isCameraReady = false
    /// Last error surfaced to the user.
    var lastErrorMessage: String?

    /// Quality readout from live frame analysis (0–1). Drives the auto-capture indicator.
    var frameQuality: Double = 0

    /// Franchise to match against (Pokémon vs ONE PIECE); set before capture from the scanner UI.
    var scanBrand: TCGBrand = .pokemon

    /// When `true`, user must pick a franchise first (multi-brand); auto-capture stays off.
    var requiresBrandSelection: Bool = false

    /// ONE PIECE only: last capture / match diagnostics for the debug “i” sheet.
    var onePieceDebugText: String = CardScannerViewModel.defaultOnePieceDebugBlurb
    /// ONE PIECE only: last cropped card image used for OCR debug preview.
    var onePieceDebugImage: UIImage?
    let onePieceOCRFraction: CGFloat = 0.18
    let onePieceEffectBandStart: CGFloat = 0.60
    let onePieceEffectBandEnd: CGFloat = 0.82
    /// ONE PIECE only: perspective-corrected full-card image used for late art-hash disambiguation.
    private var onePieceHashSourceImage: UIImage?

    // MARK: - Callbacks
    var onMatch: ((ScanResult) -> Void)?

    // MARK: - Private

    private var cardDataService: CardDataService?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "scanner.video", qos: .userInitiated)
    /// Serial queue for all `AVCaptureSession` mutations and `startRunning` / `stopRunning` (must not block the main thread).
    private let sessionQueue = DispatchQueue(label: "scanner.capture.session", qos: .userInitiated)
    private var didConfigureSession = false

    /// Normalized rect (0–1) of the card reticle within the screen.
    var cardNormalizedRect: CGRect = .zero

    private let ciContext = CIContext(options: nil)

    // Auto-capture state
    private var autoCaptureFrameCount = 0       // consecutive good frames
    private let autoCaptureThreshold = 8        // frames needed before firing
    /// Same value as `CardScannerReticle` green / “Hold steady” threshold.
    private let autoCaptureMinQuality: Double = 0.45
    private var lastAutoCaptureTime: Date = .distantPast
    /// Minimum time after a finished scan (or attempted capture) before auto-capture can run again.
    private let autoCaptureMinInterval: TimeInterval = 2.0
    private var isAnalysingFrame = false        // prevent overlapping Vision calls

    // MARK: - Setup

    func configure(cardDataService: CardDataService) {
        self.cardDataService = cardDataService
    }

    fileprivate static let defaultOnePieceDebugBlurb = """
    ONE PIECE scanner uses the bottom 18% of the cropped card image for footer OCR and the 60–82% band for effect OCR.

    Debug output from the last capture attempt will appear here after you scan.
    """

    private func setOnePieceDebug(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onePieceDebugText = text
        }
    }

    func startSession() {
        guard AVCaptureDevice.authorizationStatus(for: .video) != .denied else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.setupCaptureSession()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// Resets error state and resumes live preview (camera stays live between scans now,
    /// so this is mainly used to clear an error and re-enable auto-capture).
    func clearError() {
        lastErrorMessage = nil
        scanState = .idle
        autoCaptureFrameCount = 0
    }

    /// User chose a different catalog match for an existing scan (same OCR). Previous pick moves into alternatives.
    func replaceScanResult(id: UUID, with newCard: Card) {
        guard let i = scanResults.firstIndex(where: { $0.id == id }) else { return }
        let old = scanResults[i]
        guard old.card.masterCardId != newCard.masterCardId else { return }
        var newAlternatives: [Card] = [old.card]
        for c in old.alternativeCards where c.masterCardId != newCard.masterCardId {
            newAlternatives.append(c)
        }
        var seen = Set<String>()
        newAlternatives = newAlternatives.filter { seen.insert($0.masterCardId).inserted }
        scanResults[i] = ScanResult(id: old.id, card: newCard, alternativeCards: newAlternatives)
    }

    /// Removes the newest scan result (index 0). No-op if there are no results.
    func undoLastScan() {
        guard !scanResults.isEmpty else { return }
        scanResults.removeFirst()
        autoCaptureFrameCount = 0
    }

    /// Clears the entire current scan list (e.g. after bulk-adding every card to the collection).
    func clearAllScanResults() {
        guard !scanResults.isEmpty else { return }
        scanResults.removeAll()
        autoCaptureFrameCount = 0
        lastErrorMessage = nil
        scanState = .idle
    }

    /// Fires the still photo pipeline manually.
    func capturePhoto() {
        guard session.isRunning, !isCapturing, !requiresBrandSelection else { return }
        lastErrorMessage = nil
        isCapturing = true
        autoCaptureFrameCount = 0  // reset so we don't double-fire
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

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if self.didConfigureSession {
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    Task { @MainActor in
                        self.isCameraReady = true
                    }
                    continuation.resume()
                    return
                }

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    Task { @MainActor in
                        self.isCameraReady = false
                    }
                    continuation.resume()
                    return
                }

                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1920x1080

                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }

                // Video data output for live frame quality analysis
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }

                // Keep preview / Vision orientation aligned with portrait UI (see captureOutput).
                if let conn = self.videoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(90.0) {
                    conn.videoRotationAngle = 90.0
                }

                self.session.commitConfiguration()
                self.didConfigureSession = true
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                Task { @MainActor in
                    self.isCameraReady = true
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Still image → Vision

    private func processStillImage(_ image: UIImage) {
        scanState = .scanning

        guard let fullCG = image.cgImage else {
            DispatchQueue.main.async { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "Could not read this photo. Try again."
            }
            return
        }

        let croppedCG = fullCG.croppedToCardRect(cardNormalizedRect, imageSize: image.size) ?? fullCG
        if scanBrand == .onePiece {
            let correctedCG = preprocessCardForOCR(croppedCG) ?? croppedCG
            let debugImage = UIImage(cgImage: correctedCG)
            DispatchQueue.main.async { [weak self] in
                self?.onePieceDebugImage = debugImage
            }
            onePieceHashSourceImage = debugImage
            Task { [weak self] in
                await self?.performOnePieceOCR(on: correctedCG)
            }
        } else {
            let ocrCGImage = preprocessCardForOCR(croppedCG) ?? croppedCG
            performOCR(on: ocrCGImage)
        }
    }

    private func performOnePieceOCR(on correctedCG: CGImage) async {
        let footerCG = correctedCG.croppingToBottomFraction(onePieceOCRFraction) ?? correctedCG
        let effectCG = correctedCG.croppingBetweenTopFractions(onePieceEffectBandStart, onePieceEffectBandEnd) ?? correctedCG
        async let footerObs = recognizeText(in: footerCG)
        async let effectObs = recognizeText(in: effectCG)
        let (footerObservations, effectObservations) = await (footerObs, effectObs)
        handleOnePieceTextObservations(footerObservations, effectObservations: effectObservations)
    }

    private func performOCR(on ocrCGImage: CGImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            Task { [weak self] in
                let observations = await self?.recognizeText(in: ocrCGImage) ?? []
                if observations.isEmpty, Task.isCancelled == false {
                    DispatchQueue.main.async { [weak self] in
                        self?.scanState = .idle
                        self?.lastErrorMessage = "Text recognition failed. Try better light or retake."
                    }
                    return
                }
                self?.handleTextObservations(observations)
            }
        }
    }

    private func recognizeText(in image: CGImage) async -> [VNRecognizedTextObservation] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let results = req.results as? [VNRecognizedTextObservation] ?? []
                continuation.resume(returning: results)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.02

            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    private func preprocessCardForOCR(_ croppedCG: CGImage) -> CGImage? {
        let inputCI = CIImage(cgImage: croppedCG)
        guard let rectangle = detectCardRectangle(in: croppedCG) else { return croppedCG }

        let quad = rectangle.toCardQuad(imageWidth: croppedCG.width, imageHeight: croppedCG.height)

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = inputCI
        filter.topLeft = CGPoint(x: quad.topLeft.x, y: quad.topLeft.y)
        filter.topRight = CGPoint(x: quad.topRight.x, y: quad.topRight.y)
        filter.bottomLeft = CGPoint(x: quad.bottomLeft.x, y: quad.bottomLeft.y)
        filter.bottomRight = CGPoint(x: quad.bottomRight.x, y: quad.bottomRight.y)

        guard let output = filter.outputImage,
              let corrected = ciContext.createCGImage(output, from: output.extent.integral)
        else { return croppedCG }
        return corrected
    }

    private func detectCardRectangle(in image: CGImage) -> VNRectangleObservation? {
        let expectedAspect = 63.0 / 88.0
        var observations = detectRectangles(
            in: image, minimumConfidence: 0.45, minimumAspectRatio: 0.5,
            maximumAspectRatio: 0.92, quadratureTolerance: 22,
            minimumSize: 0.22, maximumObservations: 10
        )
        if observations.isEmpty, let enhanced = rectangleDetectionImage(from: image) {
            observations = detectRectangles(
                in: enhanced, minimumConfidence: 0.25, minimumAspectRatio: 0.45,
                maximumAspectRatio: 0.95, quadratureTolerance: 28,
                minimumSize: 0.16, maximumObservations: 14
            )
        }
        guard !observations.isEmpty else { return nil }
        return observations.max {
            rectangleScore($0, expectedAspect: expectedAspect) < rectangleScore($1, expectedAspect: expectedAspect)
        }
    }

    private func detectRectangles(
        in image: CGImage,
        minimumConfidence: VNConfidence,
        minimumAspectRatio: VNAspectRatio,
        maximumAspectRatio: VNAspectRatio,
        quadratureTolerance: VNDegrees,
        minimumSize: Float,
        maximumObservations: Int
    ) -> [VNRectangleObservation] {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = maximumObservations
        request.minimumConfidence = minimumConfidence
        request.minimumAspectRatio = minimumAspectRatio
        request.maximumAspectRatio = maximumAspectRatio
        request.quadratureTolerance = quadratureTolerance
        request.minimumSize = minimumSize
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return request.results ?? []
    }

    private func rectangleDetectionImage(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let controls = CIFilter.colorControls()
        controls.inputImage = input
        controls.saturation = 0
        controls.contrast = 1.45
        controls.brightness = 0.02
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = controls.outputImage
        exposure.ev = 0.35
        guard let output = exposure.outputImage else { return nil }
        return ciContext.createCGImage(output, from: input.extent.integral)
    }

    private func rectangleScore(_ observation: VNRectangleObservation, expectedAspect: Double) -> Double {
        let widthTop = hypot(observation.topRight.x - observation.topLeft.x, observation.topRight.y - observation.topLeft.y)
        let widthBottom = hypot(observation.bottomRight.x - observation.bottomLeft.x, observation.bottomRight.y - observation.bottomLeft.y)
        let heightLeft = hypot(observation.topLeft.x - observation.bottomLeft.x, observation.topLeft.y - observation.bottomLeft.y)
        let heightRight = hypot(observation.topRight.x - observation.bottomRight.x, observation.topRight.y - observation.bottomRight.y)
        let avgWidth = (widthTop + widthBottom) / 2
        let avgHeight = (heightLeft + heightRight) / 2
        let aspect = avgWidth / max(avgHeight, 0.0001)
        let aspectPenalty = abs(aspect - expectedAspect) * 3.5
        let area = Double(observation.boundingBox.width * observation.boundingBox.height)
        let centerX = Double(observation.boundingBox.midX)
        let centerY = Double(observation.boundingBox.midY)
        let distanceFromCenter = hypot(centerX - 0.5, centerY - 0.5)
        let centerBonus = max(0, 1 - distanceFromCenter * 1.8) * 0.16
        let edgeInset = min(observation.boundingBox.minX, observation.boundingBox.minY,
                            1 - observation.boundingBox.maxX, 1 - observation.boundingBox.maxY)
        let edgePenalty = edgeInset < 0.015 ? 0.08 : 0
        return area + centerBonus - aspectPenalty - edgePenalty
    }

    // MARK: - OCR result parsing

    private func handleTextObservations(_ observations: [VNRecognizedTextObservation]) {
        if scanBrand == .onePiece {
            handleOnePieceTextObservations(observations)
            return
        }
        let sortedLines = CardOCRFieldExtractor.sortedLinesForDebug(from: observations)
        let fields = CardOCRFieldExtractor.extract(from: observations)

        guard !sortedLines.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "No text found. Try more light or a closer shot."
            }
            return
        }

        let hasNarrowSignal = [
            fields.name.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
            fields.hp.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
            fields.centerSearchHint.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
        ].contains(true)

        guard hasNarrowSignal else {
            DispatchQueue.main.async { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "Could not read card name, HP, or attack text. Try again."
            }
            return
        }

        let numberCandidates = CardOCRFieldExtractor.extractCardNumberCandidates(from: sortedLines)
        let rawBlob = sortedLines.joined(separator: "\n")

        Task { [weak self] in
            await self?.runSearch(
                cardName: fields.name,
                hp: fields.hp,
                setNumber: fields.setNumber,
                illustrator: fields.illustrator,
                centerHint: fields.centerSearchHint,
                numberCandidates: numberCandidates,
                rawOCRBlob: rawBlob
            )
        }
    }

    private func handleOnePieceTextObservations(
        _ observations: [VNRecognizedTextObservation],
        effectObservations: [VNRecognizedTextObservation] = []
    ) {
        let sortedLines = CardOCRFieldExtractor.sortedLinesForDebug(from: observations)
        let effectLines = CardOCRFieldExtractor.sortedLinesForDebug(from: effectObservations)
        let fields = CardOCRFieldExtractor.extractOnePiece(from: observations, effectObservations: effectObservations)
        let debugHeader = Self.formatOnePieceDebugHeader(
            observationCount: observations.count,
            sortedLines: sortedLines,
            name: fields.name,
            cardType: fields.cardType,
            subtype: fields.subtype,
            cardNumber: fields.cardNumber,
            effectLines: effectLines,
            effectText: fields.effectText
        )

        guard !sortedLines.isEmpty else {
            setOnePieceDebug(debugHeader + "\nResult: FAIL — no OCR lines.")
            DispatchQueue.main.async { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "No text found. Try more light or a closer shot."
            }
            return
        }

        let hasSignal = [
            fields.cardType.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
            fields.name.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
            fields.cardNumber.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false,
        ].contains(true)

        guard hasSignal else {
            setOnePieceDebug(debugHeader + "\nResult: FAIL — no supertype / name / number in cropped bottom strip.")
            DispatchQueue.main.async { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "Could not read the bottom of the card. Try again."
            }
            return
        }

        var numberCandidates: [String] = []
        if let n = fields.cardNumber, !n.isEmpty { numberCandidates.append(n) }
        for line in sortedLines where line.contains("-") && line.range(of: #"[A-Za-z]\d"#, options: .regularExpression) != nil {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !numberCandidates.contains(t) { numberCandidates.append(t) }
        }

        let rawBlob = sortedLines.joined(separator: "\n")
        let ncSummary = numberCandidates.joined(separator: ", ")
        let headerWithCandidates = debugHeader + "\nNumber candidates: \(ncSummary.isEmpty ? "∅" : ncSummary)\n"

        Task { [weak self] in
            await self?.runSearchOnePiece(
                supertype: fields.cardType,
                cardName: fields.name,
                cardNumber: fields.cardNumber,
                subtype: fields.subtype,
                effectText: fields.effectText,
                numberCandidates: numberCandidates,
                rawOCRBlob: ([rawBlob] + effectLines).filter { !$0.isEmpty }.joined(separator: "\n"),
                debugHeader: headerWithCandidates
            )
        }
    }

    private static func formatOnePieceDebugHeader(
        observationCount: Int,
        sortedLines: [String],
        name: String?,
        cardType: String?,
        subtype: String?,
        cardNumber: String?,
        effectLines: [String],
        effectText: String?
    ) -> String {
        var s = "ONE PIECE scan debug\n"
        s += "OCR regions: bottom 18% footer strip + 60–82% effect band.\n"
        s += "Vision text observations: \(observationCount)\n\n"
        s += "Extracted fields (bottom band):\n"
        s += "  • supertype: \(cardType ?? "∅")\n"
        s += "  • name: \(name ?? "∅")\n"
        s += "  • subtype: \(subtype ?? "∅")\n"
        s += "  • cardNumber: \(cardNumber ?? "∅")\n\n"
        s += "All OCR lines (reading order):\n"
        for (i, line) in sortedLines.prefix(30).enumerated() {
            s += "  \(i + 1). \(line)\n"
        }
        if sortedLines.count > 30 {
            s += "  … (\(sortedLines.count - 30) more lines)\n"
        }
        s += "\nEffect band lines:\n"
        if effectLines.isEmpty {
            s += "  ∅\n"
        } else {
            for (i, line) in effectLines.prefix(18).enumerated() {
                s += "  \(i + 1). \(line)\n"
            }
            if effectLines.count > 18 {
                s += "  … (\(effectLines.count - 18) more lines)\n"
            }
        }
        s += "Extracted effect: \(effectText ?? "∅")\n"
        return s
    }

    private static func cleanedOCRName(_ name: String?) -> String? {
        guard var t = name?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        t = t.replacingOccurrences(of: #"[|]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^[^A-Za-z]+|[^A-Za-z]+$"#, with: "", options: .regularExpression)
        let tokens = t.split(whereSeparator: \.isWhitespace).map(String.init)
        let cleanedTokens = tokens.filter { token in
            let letters = token.filter(\.isLetter)
            guard letters.count >= 2 else { return false }
            return Double(letters.count) / Double(max(token.count, 1)) >= 0.55
        }
        let cleaned = cleanedTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func preferredOnePieceNameQuery(rawName: String?, cleanedName: String?) -> String? {
        let raw = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned = cleanedName, !cleaned.isEmpty {
            let rawWordCount = raw?.split(whereSeparator: \.isWhitespace).count ?? 0
            let rawLooksNoisy = (raw?.count ?? 0) > 28 || rawWordCount > 5
            if rawLooksNoisy || cleaned.count < (raw?.count ?? .max) {
                return cleaned
            }
        }
        return raw ?? cleanedName
    }

    private func mixedFallbackPool(
        service: CardDataService, cleanedName: String?, hp: String?,
        setNumber: String?, illustrator: String?, centerHint: String?,
        catalogBrand: TCGBrand
    ) async -> [Card] {
        var combined: [Card] = []
        if let cleanedName, !cleanedName.isEmpty {
            combined.append(contentsOf: await service.searchByName(query: cleanedName, catalogBrand: catalogBrand))
            combined.append(contentsOf: await service.search(query: cleanedName, catalogBrand: catalogBrand))
        }
        if let setNumber, !setNumber.isEmpty {
            combined.append(contentsOf: await service.search(query: setNumber, catalogBrand: catalogBrand))
        }
        if let illustrator, !illustrator.isEmpty {
            combined.append(contentsOf: await service.search(query: illustrator, catalogBrand: catalogBrand))
        }
        if let centerHint, !centerHint.isEmpty {
            combined.append(contentsOf: await service.searchSoftTokenMatch(query: centerHint, catalogBrand: catalogBrand))
        }
        var deduped = Self.dedupCards(combined)
        if catalogBrand == .pokemon, let hp, let ocrHP = Int(hp.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let exactHP = deduped.filter { $0.hp == nil || $0.hp == ocrHP }
            if !exactHP.isEmpty { deduped = exactHP }
        }
        return deduped
    }

    private func orderedTokenPatternScore(pattern: [String], tokens: [String]) -> Int {
        guard !pattern.isEmpty, !tokens.isEmpty else { return 0 }

        var matchedIndices: [Int] = []
        var searchStart = 0
        for part in pattern {
            guard let idx = tokens[searchStart...].firstIndex(of: part) else {
                return matchedIndices.count * 90_000
            }
            matchedIndices.append(idx)
            searchStart = idx + 1
        }

        guard let first = matchedIndices.first, let last = matchedIndices.last else { return 0 }
        let span = max(last - first, 0)
        return pattern.count * 170_000 + max(0, 5 - span) * 25_000
    }

    private func runSearchOnePiece(
        supertype: String?,
        cardName: String?,
        cardNumber: String?,
        subtype: String?,
        effectText: String?,
        numberCandidates: [String],
        rawOCRBlob: String?,
        debugHeader: String
    ) async {
        guard let service = cardDataService else { return }
        let brand = TCGBrand.onePiece

        let rawSupertype = supertype?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = cardName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = Self.cleanedOCRName(rawName)
        let preferredNameQuery = Self.preferredOnePieceNameQuery(rawName: rawName, cleanedName: cleanedName)
        let hasName = !(preferredNameQuery?.isEmpty ?? true)

        var pool: [Card] = []
        var searchPath = ""
        if hasName {
            searchPath = "searchByName(\"\(preferredNameQuery!)\")"
            pool = await service.searchByName(query: preferredNameQuery!, catalogBrand: brand)
            if pool.isEmpty, let cleanedName, cleanedName.caseInsensitiveCompare(preferredNameQuery!) != .orderedSame {
                searchPath += " → searchByName(cleaned)"
                pool = await service.searchByName(query: cleanedName, catalogBrand: brand)
            }
            if pool.isEmpty, let cleanedName {
                searchPath += " → search / softMatch"
                pool = await service.search(query: cleanedName, catalogBrand: brand)
                if pool.isEmpty { pool = await service.searchSoftTokenMatch(query: cleanedName, catalogBrand: brand) }
            }
        } else if let num = cardNumber, !num.isEmpty {
            searchPath = "search(\"\(num)\")"
            pool = await service.search(query: num, catalogBrand: brand)
        }

        if pool.isEmpty {
            searchPath += " → mixedFallback"
            pool = await mixedFallbackPool(
                service: service, cleanedName: cleanedName, hp: nil,
                setNumber: cardNumber, illustrator: nil, centerHint: nil,
                catalogBrand: brand
            )
        }

        if let rawSupertype, !rawSupertype.isEmpty {
            let filtered = pool.filter { card in
                let category = card.category?.lowercased() ?? ""
                let needle = rawSupertype.lowercased()
                return category.contains(needle)
            }
            if !filtered.isEmpty {
                searchPath += " → filter(supertype: \(rawSupertype))"
                pool = filtered
            }
        }

        let mergedRaw = ScannerCompositeRanker.mergedNumberCandidates(primary: cardNumber, extras: numberCandidates)
        var mergedNumbers: [String] = []
        var seenNorm = Set<String>()
        for m in mergedRaw {
            let n = CardOCRFieldExtractor.normalizedOnePieceCollectorID(m)
            if !n.isEmpty, !seenNorm.contains(n) {
                seenNorm.insert(n)
                mergedNumbers.append(n)
            }
        }
        if mergedNumbers.isEmpty {
            mergedNumbers = mergedRaw
        }
        let numberReadable = CardOCRFieldExtractor.onePieceOCRHasReadableCollectorNumber(mergedRaw)
        let scorePrimary = mergedNumbers.first ?? cardNumber
        let scoreExtras = mergedNumbers.count > 1 ? Array(mergedNumbers.dropFirst()) : []

        if !numberReadable {
            if let subtype, !subtype.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let scored = pool.map { card in
                    (card, ScannerCompositeRanker.onePieceSubtypeScoreDebug(ocrSubtype: subtype, card: card))
                }
                let filtered = scored.filter { $0.1 > 0 }.map(\.0)
                if !filtered.isEmpty {
                    let best = scored.map(\.1).max() ?? 0
                    searchPath += " → filter(subtype, best: \(best))"
                    pool = filtered
                }
            }

            if let effectText, !effectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let scored = pool.map { card in
                    (card, ScannerCompositeRanker.onePieceEffectScoreDebug(ocrEffect: effectText, card: card))
                }
                let filtered = scored.filter { $0.1 > 0 }.map(\.0)
                if !filtered.isEmpty {
                    let best = scored.map(\.1).max() ?? 0
                    searchPath += " → filter(effect, best: \(best))"
                    pool = filtered
                }
            }
        } else {
            searchPath += " → collector# readable (subtype/effect not used to narrow)"
        }

        let mergedNormSet: Set<String> = Set(mergedNumbers.compactMap { raw in
            let n = CardOCRFieldExtractor.normalizedOnePieceCollectorID(raw)
            return n.isEmpty ? nil : n
        })

        /// OCR read a collector id but name search can miss rows. Only merge catalog matches that still belong to the **same**
        /// name + supertype slice as the pool (card number ranking never pulls arbitrary ids).
        if numberReadable, !mergedNormSet.isEmpty {
            let before = pool.count
            var seenIDs = Set(pool.map(\.masterCardId))
            for key in mergedNormSet {
                let rows = await service.allOnePieceCardsMatchingNormalizedCollectorID(key)
                for c in rows {
                    guard seenIDs.insert(c.masterCardId).inserted else { continue }
                    if let rawSupertype, !rawSupertype.isEmpty {
                        let cat = c.category?.lowercased() ?? ""
                        if !cat.contains(rawSupertype.lowercased()) { continue }
                    }
                    if hasName {
                        let sPreferred = ScannerCompositeRanker.nameScore(ocrName: preferredNameQuery, card: c)
                        let sCleaned = cleanedName.map { ScannerCompositeRanker.nameScore(ocrName: $0, card: c) } ?? 0
                        guard max(sPreferred, sCleaned) > 0 else { continue }
                    }
                    pool.append(c)
                }
            }
            if pool.count > before {
                searchPath += " → merge \(pool.count - before) catalog card(s) for OCR collector id (same name+supertype)"
            }
        }

        let rankedByNumber = pool.sorted { a, b in
            if !mergedNormSet.isEmpty {
                let na = CardOCRFieldExtractor.normalizedOnePieceCollectorID(a.cardNumber)
                let nb = CardOCRFieldExtractor.normalizedOnePieceCollectorID(b.cardNumber)
                let aExact = mergedNormSet.contains(na)
                let bExact = mergedNormSet.contains(nb)
                if aExact != bExact { return aExact && !bExact }
            }
            let sa = ScannerCompositeRanker.bestOnePieceNumberScoreDebug(card: a, candidates: mergedNumbers)
            let sb = ScannerCompositeRanker.bestOnePieceNumberScoreDebug(card: b, candidates: mergedNumbers)
            if sa != sb { return sa > sb }
            let ta = ScannerCompositeRanker.onePieceTotalScoreDebug(
                card: a,
                ocrName: preferredNameQuery,
                ocrSupertype: rawSupertype,
                ocrCardNumber: scorePrimary,
                ocrSubtype: subtype,
                ocrEffect: effectText,
                numberCandidates: scoreExtras,
                rawOCRBlob: rawOCRBlob,
                includeSubtypeAndEffect: !numberReadable
            )
            let tb = ScannerCompositeRanker.onePieceTotalScoreDebug(
                card: b,
                ocrName: preferredNameQuery,
                ocrSupertype: rawSupertype,
                ocrCardNumber: scorePrimary,
                ocrSubtype: subtype,
                ocrEffect: effectText,
                numberCandidates: scoreExtras,
                rawOCRBlob: rawOCRBlob,
                includeSubtypeAndEffect: !numberReadable
            )
            if ta != tb { return ta > tb }
            return a.masterCardId < b.masterCardId
        }

        if !mergedNumbers.isEmpty, let bestCard = rankedByNumber.first {
            let best = ScannerCompositeRanker.bestOnePieceNumberScoreDebug(card: bestCard, candidates: mergedNumbers)
            searchPath += " → rank(cardNumber closest, best: \(best), top: \(bestCard.cardNumber))"
        }

        let rankedByText = ScannerCompositeRanker.rankOnePiece(
            pool,
            ocrName: preferredNameQuery,
            ocrSupertype: rawSupertype,
            ocrCardNumber: scorePrimary,
            ocrSubtype: subtype,
            ocrEffect: effectText,
            numberCandidates: scoreExtras,
            rawOCRBlob: rawOCRBlob,
            includeSubtypeAndEffect: !numberReadable
        )

        let rankedByTextIDs = Dictionary(uniqueKeysWithValues: rankedByText.enumerated().map { ($1.masterCardId, $0) })
        let preHashRanked = rankedByNumber.sorted { a, b in
            if !mergedNormSet.isEmpty {
                let na = CardOCRFieldExtractor.normalizedOnePieceCollectorID(a.cardNumber)
                let nb = CardOCRFieldExtractor.normalizedOnePieceCollectorID(b.cardNumber)
                let aExact = mergedNormSet.contains(na)
                let bExact = mergedNormSet.contains(nb)
                if aExact != bExact { return aExact && !bExact }
            }
            let sa = ScannerCompositeRanker.bestOnePieceNumberScoreDebug(card: a, candidates: mergedNumbers)
            let sb = ScannerCompositeRanker.bestOnePieceNumberScoreDebug(card: b, candidates: mergedNumbers)
            if sa != sb { return sa > sb }
            let ia = rankedByTextIDs[a.masterCardId] ?? .max
            let ib = rankedByTextIDs[b.masterCardId] ?? .max
            if ia != ib { return ia < ib }
            return a.masterCardId < b.masterCardId
        }

        let exactHashNumber = rankedByNumber.first.map { CardOCRFieldExtractor.normalizedOnePieceCollectorID($0.cardNumber) }
            .flatMap { $0.isEmpty ? nil : $0 }

        var hashCandidates: [Card] = []
        if let key = exactHashNumber, !key.isEmpty {
            let fromCatalog = await service.allOnePieceCardsMatchingNormalizedCollectorID(key)
            let preHashOrder = Dictionary(uniqueKeysWithValues: preHashRanked.enumerated().map { ($1.masterCardId, $0) })
            hashCandidates = fromCatalog.sorted {
                (preHashOrder[$0.masterCardId] ?? .max) < (preHashOrder[$1.masterCardId] ?? .max)
            }
        }
        if hashCandidates.count < 2, let key = exactHashNumber, !key.isEmpty {
            let fromPool = preHashRanked.filter {
                CardOCRFieldExtractor.normalizedOnePieceCollectorID($0.cardNumber) == key
            }
            if fromPool.count > hashCandidates.count {
                hashCandidates = fromPool
            }
        }

        let hashRerank: OnePieceArtHashRerankResult? = if let captured = onePieceHashSourceImage, hashCandidates.count > 1 {
            await OnePieceArtHashMatcher.shared.rerank(candidates: hashCandidates, capturedImage: captured)
        } else {
            nil
        }
        let ranked: [Card]
        if let hashRerank {
            let hashedIDs = Set(hashRerank.ranked.map(\.masterCardId))
            ranked = hashRerank.ranked + preHashRanked.filter { !hashedIDs.contains($0.masterCardId) }
        } else {
            ranked = preHashRanked
        }

        var searchSection = "\n--- Search ---\nPath: \(searchPath.isEmpty ? "(none)" : searchPath)\nPool: \(pool.count) cards\n"

        if pool.count <= 12 {
            for c in pool {
                searchSection += "  • \(c.masterCardId) — \(c.cardName)\n"
            }
        } else {
            for c in pool.prefix(12) {
                searchSection += "  • \(c.masterCardId) — \(c.cardName)\n"
            }
            searchSection += "  … (\(pool.count - 12) more)\n"
        }

        if let hashRerank, !hashRerank.matches.isEmpty {
            searchSection += "\n--- Art Hash ---\n"
            searchSection += "Compared corrected capture against \(hashRerank.matches.count) candidate arts with exact card number \(exactHashNumber ?? "∅").\n"
            for match in hashRerank.matches.prefix(8) {
                searchSection += "  • dHash distance \(match.distance): \(match.card.masterCardId) — \(match.card.cardName)\n"
            }
            if hashRerank.matches.count > 8 {
                searchSection += "  … (\(hashRerank.matches.count - 8) more)\n"
            }
        }

        guard let top = ranked.first else {
            setOnePieceDebug(debugHeader + searchSection + "\nResult: FAIL — empty pool after ranking.")
            await MainActor.run { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "No catalog match for that text. Try again."
            }
            return
        }

        let alternatives = Array(ranked.dropFirst().prefix(30))

        let topScore = ScannerCompositeRanker.onePieceTotalScoreDebug(
            card: top,
            ocrName: preferredNameQuery,
            ocrSupertype: rawSupertype,
            ocrCardNumber: scorePrimary,
            ocrSubtype: subtype,
            ocrEffect: effectText,
            numberCandidates: scoreExtras,
            rawOCRBlob: rawOCRBlob,
            includeSubtypeAndEffect: !numberReadable
        )
        let topSubtype = top.subtype ?? top.subtypes?.joined(separator: ", ") ?? "∅"
        searchSection += "\nRanked #1: \(top.masterCardId)\n"
        searchSection += "  name: \(top.cardName)\n"
        searchSection += "  subtype: \(topSubtype)\n"
        searchSection += "  composite score: \(topScore)\n"
        searchSection += "Alternatives in UI: \(alternatives.count)\n"
        if let second = ranked.dropFirst().first {
            let s2 = ScannerCompositeRanker.onePieceTotalScoreDebug(
                card: second,
                ocrName: preferredNameQuery,
                ocrSupertype: rawSupertype,
                ocrCardNumber: scorePrimary,
                ocrSubtype: subtype,
                ocrEffect: effectText,
                numberCandidates: scoreExtras,
                rawOCRBlob: rawOCRBlob,
                includeSubtypeAndEffect: !numberReadable
            )
            searchSection += "Ranked #2: \(second.masterCardId) — \(second.cardName) (score \(s2))\n"
        }

        let finalSearchSection = searchSection
        await MainActor.run { [weak self] in
            guard let self else { return }
            scanState = .idle
            lastErrorMessage = nil
            autoCaptureFrameCount = 0
            lastAutoCaptureTime = Date()
            if let newest = scanResults.first, newest.card.masterCardId == top.masterCardId {
                self.setOnePieceDebug(debugHeader + finalSearchSection + "\nResult: skipped duplicate (same card as previous scan).")
                return
            }
            let result = ScanResult(card: top, alternativeCards: alternatives)
            scanResults.insert(result, at: 0)
            self.setOnePieceDebug(debugHeader + finalSearchSection + "\nResult: OK — match accepted.")
            onMatch?(result)
        }
    }

    private static func dedupCards(_ cards: [Card]) -> [Card] {
        var seen = Set<String>()
        var out: [Card] = []
        for card in cards where seen.insert(card.masterCardId).inserted {
            out.append(card)
        }
        return out
    }

    private func runSearch(
        cardName: String?, hp: String?, setNumber: String?,
        illustrator: String?, centerHint: String?,
        numberCandidates: [String], rawOCRBlob: String?
    ) async {
        guard let service = cardDataService else { return }
        /// Must match the brand the user picked in the scanner — not `BrandSettings.selectedCatalogBrand` (browse tab).
        let brand = scanBrand

        let rawName = cardName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = Self.cleanedOCRName(rawName)
        let hasName = !(rawName?.isEmpty ?? true)

        var pool: [Card]
        if hasName {
            pool = await service.searchByName(query: rawName!, catalogBrand: brand)
            if pool.isEmpty, let cleanedName, cleanedName.caseInsensitiveCompare(rawName!) != .orderedSame {
                pool = await service.searchByName(query: cleanedName, catalogBrand: brand)
            }
            if pool.isEmpty, let cleanedName {
                pool = await service.search(query: cleanedName, catalogBrand: brand)
                if pool.isEmpty { pool = await service.searchSoftTokenMatch(query: cleanedName, catalogBrand: brand) }
            }
        } else if let hint = centerHint, !hint.isEmpty {
            pool = await service.search(query: hint, catalogBrand: brand)
            if pool.isEmpty { pool = await service.searchSoftTokenMatch(query: hint, catalogBrand: brand) }
        } else {
            pool = []
        }

        if pool.isEmpty {
            pool = await mixedFallbackPool(
                service: service, cleanedName: cleanedName, hp: hp,
                setNumber: setNumber, illustrator: illustrator, centerHint: centerHint,
                catalogBrand: brand
            )
        }

        let ranked = ScannerCompositeRanker.rank(
            pool, ocrName: cleanedName ?? rawName, ocrHP: hp,
            ocrCenterHint: centerHint, primaryCardNumber: setNumber,
            extraNumberCandidates: numberCandidates,
            ocrIllustrator: illustrator, rawOCRBlob: rawOCRBlob
        )

        guard let top = ranked.first else {
            await MainActor.run { [weak self] in
                self?.scanState = .idle
                self?.lastErrorMessage = "No catalog match for that text. Try again."
            }
            return
        }

        let alternatives = Array(ranked.dropFirst().prefix(30))

        await MainActor.run { [weak self] in
            guard let self else { return }
            scanState = .idle
            lastErrorMessage = nil
            autoCaptureFrameCount = 0
            // Enforce cooldown before another auto-capture (do not reset to `.distantPast` — that caused double scans).
            lastAutoCaptureTime = Date()
            // Skip duplicate of the most recent result (same physical card still in frame).
            if let newest = scanResults.first, newest.card.masterCardId == top.masterCardId {
                return
            }
            let result = ScanResult(card: top, alternativeCards: alternatives)
            scanResults.insert(result, at: 0)
            onMatch?(result)
        }
    }
}

// MARK: - Auto-capture (AVCaptureVideoDataOutputSampleBufferDelegate)

extension CardScannerViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Don't analyse while a capture or OCR pass is in flight
        guard !isCapturing, case .idle = scanState else {
            DispatchQueue.main.async { [weak self] in self?.frameQuality = 0 }
            return
        }
        guard !requiresBrandSelection else {
            DispatchQueue.main.async { [weak self] in self?.frameQuality = 0 }
            return
        }
        guard !isAnalysingFrame else { return }
        guard Date().timeIntervalSince(lastAutoCaptureTime) >= autoCaptureMinInterval else { return }

        isAnalysingFrame = true
        defer { isAnalysingFrame = false }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Pass the buffer directly to Vision. Orientation must match AVCaptureConnection.videoRotationAngle
        // (set to 90.0 in setup) so bounding boxes line up with the on-screen reticle.
        let visionOrientation = Self.cgImageOrientation(forVideoRotationAngle: connection.videoRotationAngle)
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = 0.3
        request.minimumAspectRatio = 0.4   // width/height; portrait card ≈ 63/88
        request.maximumAspectRatio = 0.95
        request.quadratureTolerance = 30
        request.minimumSize = 0.1

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: visionOrientation, options: [:])
        try? handler.perform([request])

        let observations = request.results ?? []
        let quality = frameQualityScore(observations, visionOrientation: visionOrientation)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameQuality = quality

            if quality >= self.autoCaptureMinQuality {
                self.autoCaptureFrameCount += 1
                if self.autoCaptureFrameCount >= self.autoCaptureThreshold {
                    self.autoCaptureFrameCount = 0
                    self.lastAutoCaptureTime = Date()
                    self.capturePhoto()
                }
            } else {
                if self.autoCaptureFrameCount > 0 { self.autoCaptureFrameCount -= 1 }
            }
        }
    }

    /// Returns 0–1 quality score.
    ///
    /// Vision uses normalized coordinates, origin bottom-left. The reticle uses UIKit top-left
    /// normalized coords. `visionOrientation` must match the handler used for detection.
    private func frameQualityScore(_ observations: [VNRectangleObservation], visionOrientation: CGImagePropertyOrientation) -> Double {
        guard !observations.isEmpty else { return 0 }

        let r = cardNormalizedRect.isEmpty
            ? CGRect(x: 0.175, y: 0.175, width: 0.65, height: 0.65)
            : cardNormalizedRect

        let visionReticle = Self.uiKitNormalizedRectToVision(r, imageOrientation: visionOrientation)

        // Physical card ~63×88 mm → axis-aligned box aspect is either ~63/88 or ~88/63 depending on rotation.
        let expectedNarrow = 63.0 / 88.0
        let expectedWide = 88.0 / 63.0

        var bestScore = 0.0
        for obs in observations {
            let bb = obs.boundingBox

            let intersection = bb.intersection(visionReticle)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }
            let overlapRatio = (intersection.width * intersection.height) / (visionReticle.width * visionReticle.height)
            guard overlapRatio > 0.2 else { continue }

            let w = bb.width
            let h = bb.height
            let wh = w / max(h, 0.001)
            let aspectDiff = min(abs(wh - expectedNarrow), abs(wh - expectedWide))
            guard aspectDiff < 0.55 else { continue }

            let aspectScore = max(0.0, 1.0 - aspectDiff / 0.55)
            let fillScore   = min(1.0, overlapRatio / 0.6)
            let confScore   = Double(obs.confidence)
            let score = confScore * 0.35 + aspectScore * 0.40 + fillScore * 0.25
            bestScore = max(bestScore, score)
        }
        return bestScore
    }

    /// Maps `videoRotationAngle` to the `CGImagePropertyOrientation` Vision expects for the
    /// same preview rotation. See “Displaying camera content” / matching preview to still analysis.
    private static func cgImageOrientation(forVideoRotationAngle angle: CGFloat) -> CGImagePropertyOrientation {
        switch angle {
        case 90.0: return .right
        case 270.0: return .left
        case 0.0: return .up
        case 180.0: return .down
        default: return .right
        }
    }

    /// Converts a normalized UIKit rect (origin top-left, y down) into Vision’s normalized space
    /// (origin bottom-left, y up) for the same `CGImagePropertyOrientation` passed to `VNImageRequestHandler`.
    ///
    /// For `.right` (typical back camera + portrait `videoRotationAngle`), this matches the reticle mapping
    /// used when converting CIImage / pixel buffers for Vision: x/y axes swap vs screen space.
    private static func uiKitNormalizedRectToVision(_ r: CGRect, imageOrientation: CGImagePropertyOrientation) -> CGRect {
        let x = r.minX, y = r.minY, w = r.width, h = r.height
        switch imageOrientation {
        case .right:
            return CGRect(x: y, y: 1 - x - w, width: h, height: w)
        case .left:
            return CGRect(x: 1 - y - h, y: x, width: h, height: w)
        case .up:
            return CGRect(x: x, y: 1 - y - h, width: w, height: h)
        case .down:
            return CGRect(x: 1 - x - w, y: y, width: w, height: h)
        case .upMirrored:
            return CGRect(x: 1 - x - w, y: 1 - y - h, width: w, height: h)
        case .downMirrored:
            return CGRect(x: x, y: y, width: w, height: h)
        case .leftMirrored:
            return CGRect(x: 1 - y - h, y: 1 - x - w, width: h, height: w)
        case .rightMirrored:
            return CGRect(x: y, y: x, width: h, height: w)
        @unknown default:
            return CGRect(x: y, y: 1 - x - w, width: h, height: w)
        }
    }
}

// MARK: - Composite ranking

private enum ScannerCompositeRanker {
    private static let attackContributionCap = 380_000

    static func mergedNumberCandidates(primary: String?, extras: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        if let p = primary?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            seen.insert(p); out.append(p)
        }
        for e in extras {
            let t = e.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t); out.append(t)
        }
        return out
    }

    static func rank(
        _ cards: [Card], ocrName: String?, ocrHP: String?, ocrCenterHint: String?,
        primaryCardNumber: String?, extraNumberCandidates: [String],
        ocrIllustrator: String? = nil, rawOCRBlob: String?
    ) -> [Card] {
        let ocrCenter = ocrCenterHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let merged = mergedNumberCandidates(primary: primaryCardNumber, extras: extraNumberCandidates)
        return cards.sorted { a, b in
            let ta = totalRankScore(card: a, ocrName: ocrName, ocrHP: ocrHP, ocrCenter: ocrCenter,
                                   numberCandidates: merged, ocrIllustrator: ocrIllustrator, rawOCRBlob: rawOCRBlob)
            let tb = totalRankScore(card: b, ocrName: ocrName, ocrHP: ocrHP, ocrCenter: ocrCenter,
                                   numberCandidates: merged, ocrIllustrator: ocrIllustrator, rawOCRBlob: rawOCRBlob)
            if ta != tb { return ta > tb }
            return a.masterCardId < b.masterCardId
        }
    }

    /// ONE PIECE: filter by supertype, name, and collector id; subtype/effect are optional (see ``includeSubtypeAndEffect``).
    static func rankOnePiece(
        _ cards: [Card],
        ocrName: String?,
        ocrSupertype: String?,
        ocrCardNumber: String?,
        ocrSubtype: String?,
        ocrEffect: String?,
        numberCandidates: [String],
        rawOCRBlob: String?,
        includeSubtypeAndEffect: Bool = true
    ) -> [Card] {
        let merged = mergedNumberCandidates(primary: ocrCardNumber, extras: numberCandidates)
        return cards.sorted { a, b in
            let ta = onePieceRankScore(
                card: a, ocrName: ocrName, ocrSupertype: ocrSupertype, ocrSubtype: ocrSubtype,
                ocrEffect: ocrEffect, numberCandidates: merged, rawOCRBlob: rawOCRBlob,
                includeSubtypeAndEffect: includeSubtypeAndEffect
            )
            let tb = onePieceRankScore(
                card: b, ocrName: ocrName, ocrSupertype: ocrSupertype, ocrSubtype: ocrSubtype,
                ocrEffect: ocrEffect, numberCandidates: merged, rawOCRBlob: rawOCRBlob,
                includeSubtypeAndEffect: includeSubtypeAndEffect
            )
            if ta != tb { return ta > tb }
            return a.masterCardId < b.masterCardId
        }
    }

    private static func onePieceRankScore(
        card: Card,
        ocrName: String?,
        ocrSupertype: String?,
        ocrSubtype: String?,
        ocrEffect: String?,
        numberCandidates: [String],
        rawOCRBlob: String?,
        includeSubtypeAndEffect: Bool = true
    ) -> Int {
        let name = nameScore(ocrName: ocrName, card: card)
        let supertype = onePieceSupertypeScore(ocrSupertype: ocrSupertype, card: card)
        let num = bestNumberScore(card: card, candidates: numberCandidates)
        let effectScore = includeSubtypeAndEffect ? onePieceEffectScore(ocrEffect: ocrEffect, card: card) : 0
        let subtypeScore = includeSubtypeAndEffect ? onePieceSubtypeScore(ocrSubtype: ocrSubtype, card: card) : 0
        let ex = exNameConsistencyScore(ocrBlob: rawOCRBlob, card: card)
        return name + supertype + num + effectScore + subtypeScore + ex
    }

    /// Same scoring as ``rankOnePiece``; exposed for scanner debug UI.
    static func onePieceTotalScoreDebug(
        card: Card,
        ocrName: String?,
        ocrSupertype: String?,
        ocrCardNumber: String?,
        ocrSubtype: String?,
        ocrEffect: String?,
        numberCandidates: [String],
        rawOCRBlob: String?,
        includeSubtypeAndEffect: Bool = true
    ) -> Int {
        let merged = mergedNumberCandidates(primary: ocrCardNumber, extras: numberCandidates)
        return onePieceRankScore(
            card: card,
            ocrName: ocrName,
            ocrSupertype: ocrSupertype,
            ocrSubtype: ocrSubtype,
            ocrEffect: ocrEffect,
            numberCandidates: merged,
            rawOCRBlob: rawOCRBlob,
            includeSubtypeAndEffect: includeSubtypeAndEffect
        )
    }

    static func bestOnePieceNumberScoreDebug(card: Card, candidates: [String]) -> Int {
        bestNumberScore(card: card, candidates: candidates)
    }

    static func onePieceSubtypeScoreDebug(ocrSubtype: String?, card: Card) -> Int {
        onePieceSubtypeScore(ocrSubtype: ocrSubtype, card: card)
    }

    static func onePieceEffectScoreDebug(ocrEffect: String?, card: Card) -> Int {
        onePieceEffectScore(ocrEffect: ocrEffect, card: card)
    }

    static func exactOnePieceCardNumber(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = ScannerCardNumberRanker.normalizedOnePieceExactID(text)
        return normalized.isEmpty ? nil : normalized
    }

    private static func onePieceSupertypeScore(ocrSupertype: String?, card: Card) -> Int {
        guard let raw = ocrSupertype?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let category = card.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty else { return 0 }
        let ocr = raw.lowercased()
        let cat = category.lowercased()
        if ocr == cat { return 280_000 }
        if cat.contains(ocr) || ocr.contains(cat) { return 220_000 }
        return 0
    }

    private static func onePieceSubtypeScore(ocrSubtype: String?, card: Card) -> Int {
        guard let raw = ocrSubtype?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return 0 }
        let ocr = significantTokens(raw.lowercased())
        guard !ocr.isEmpty else { return 0 }

        var best = 0
        let catalogValues = ([card.subtype] + (card.subtypes ?? [])).compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for value in catalogValues {
            let cat = significantTokens(value.lowercased())
            guard !cat.isEmpty else { continue }
            let inter = ocr.intersection(cat)
            guard !inter.isEmpty else { continue }
            if ocr == cat { best = max(best, 220_000); continue }
            let recall = Double(inter.count) / Double(max(cat.count, 1))
            let precision = Double(inter.count) / Double(max(ocr.count, 1))
            best = max(best, Int((recall * 0.7 + precision * 0.3) * 185_000))
        }
        return best
    }

    private static func onePieceEffectScore(ocrEffect: String?, card: Card) -> Int {
        guard let raw = ocrEffect?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return 0 }
        return min(centerTextScore(ocrCenter: raw.lowercased(), card: card), 320_000)
    }

    private static func totalRankScore(
        card: Card, ocrName: String?, ocrHP: String?, ocrCenter: String,
        numberCandidates: [String], ocrIllustrator: String? = nil, rawOCRBlob: String?
    ) -> Int {
        let name = nameScore(ocrName: ocrName, card: card)
        let hp = hpScore(ocrHP: ocrHP, card: card)
        let rawCenter = centerTextScore(ocrCenter: ocrCenter, card: card)
        let capped = min(rawCenter, attackContributionCap)
        let num = bestNumberScore(card: card, candidates: numberCandidates)
        let artist = artistScore(ocrIllustrator: ocrIllustrator, card: card)
        let x = exNameConsistencyScore(ocrBlob: rawOCRBlob, card: card)
        return name + hp + capped + num + artist + x
    }

    static func nameScore(ocrName: String?, card: Card) -> Int {
        let ocr = significantTokens(ocrName?.lowercased() ?? "")
        let name = significantTokens(card.cardName.lowercased())
        guard !ocr.isEmpty, !name.isEmpty else { return 0 }
        let inter = ocr.intersection(name)
        guard !inter.isEmpty else { return 0 }
        if ocr == name { return 320_000 }
        let recall = Double(inter.count) / Double(max(name.count, 1))
        let precision = Double(inter.count) / Double(max(ocr.count, 1))
        return Int((recall * 0.7 + precision * 0.3) * 260_000)
    }

    static func hpScore(ocrHP: String?, card: Card) -> Int {
        guard let ocrHP = ocrHP?.trimmingCharacters(in: .whitespacesAndNewlines),
              let hp = Int(ocrHP) else { return 0 }
        guard let cardHP = card.hp else { return 30_000 }
        if cardHP == hp { return 140_000 }
        if abs(cardHP - hp) <= 10 { return 40_000 }
        return 0
    }

    private static func bestNumberScore(card: Card, candidates: [String]) -> Int {
        candidates.reduce(0) { best, c in
            max(best, ScannerCardNumberRanker.score(ocr: c, catalog: card.cardNumber))
        }
    }

    static func artistScore(ocrIllustrator: String?, card: Card) -> Int {
        let ocr = significantTokens(ocrIllustrator?.lowercased() ?? "")
        let artist = significantTokens(card.artist?.lowercased() ?? "")
        guard !ocr.isEmpty, !artist.isEmpty else { return 0 }
        let inter = ocr.intersection(artist)
        guard !inter.isEmpty else { return 0 }
        if ocr == artist { return 260_000 }
        return Int(Double(inter.count) / Double(max(artist.count, 1)) * 200_000)
    }

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

    private static func pokemonAttackOverlapScore(ocrCenter: String, attacks: [CardAttack]) -> Int {
        var catalogTokens = Set<String>()
        for a in attacks { distinctiveAttackTokens(a.name.lowercased()).forEach { catalogTokens.insert($0) } }
        guard !catalogTokens.isEmpty else { return 0 }
        let ocrTokens = distinctiveAttackTokens(ocrCenter)
        guard !ocrTokens.isEmpty else { return 0 }
        let inter = catalogTokens.intersection(ocrTokens)
        if inter.isEmpty { return 0 }
        let recall = Double(inter.count) / Double(catalogTokens.count)
        var score = Int(recall * 450_000)
        let union = catalogTokens.union(ocrTokens)
        score += Int(Double(inter.count) / Double(max(union.count, 1)) * 120_000)
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
        for t in raw where t.count >= 3 && !stopwords.contains(t) { s.insert(t) }
        return s
    }

    private static func distinctiveAttackTokens(_ text: String) -> Set<String> {
        let raw = SearchTokenizer.tokens(from: text.lowercased())
        let blocked = stopwords.union(attackNoiseStopwords)
        var s = Set<String>()
        for t in raw where t.count >= 4 && !blocked.contains(t) { s.insert(t) }
        return s
    }
}

// MARK: - Card number ranking

private enum ScannerCardNumberRanker {
    static func rank(_ cards: [Card], ocrCardNumber: String?) -> [Card] {
        guard let ocr = ocrCardNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty else { return cards }
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

        if c.contains("-") {
            return onePieceStyleScore(ocr: o, catalog: c)
        }

        let cParts = c.split(separator: "/").map(String.init)
        let oParts = o.split(separator: "/").map(String.init)
        guard cParts.count == 2 else { return (c.contains(o) || o.contains(c)) ? 50_000 : 0 }

        let cLeft = cParts[0]; let cRight = cParts[1]
        if oParts.count == 2 {
            let oLeft = oParts[0]; let oRight = oParts[1]
            var score = 0
            if intEqual(cLeft, oLeft) { score += 500_000 } else if smallDigitStringClose(cLeft, oLeft) { score += 350_000 }
            if intEqual(cRight, oRight) { score += 400_000 } else if smallDigitStringClose(cRight, oRight) { score += 250_000 }
            return score
        }
        if oParts.count == 1 {
            let fragment = oParts[0]
            if intEqual(cLeft, fragment) { return 450_000 }
            if c.hasPrefix(fragment + "/") || c.hasPrefix(fragment) { return 380_000 }
        }
        return c.contains(o) ? 40_000 : 0
    }

    static func normalizedOnePieceExactID(_ text: String) -> String {
        normalizedOnePieceID(text)
    }

    private static func onePieceStyleScore(ocr: String, catalog: String) -> Int {
        let cNorm = normalizedOnePieceID(catalog)
        let oNorm = normalizedOnePieceID(ocr)
        guard !cNorm.isEmpty, !oNorm.isEmpty else { return 0 }
        if cNorm == oNorm { return 1_000_000 }

        let cParts = cNorm.split(separator: "-").map(String.init)
        let oParts = oNorm.split(separator: "-").map(String.init)
        guard cParts.count == 2, oParts.count == 2 else {
            if cNorm.contains(oNorm) || oNorm.contains(cNorm) { return 180_000 }
            return smallAlphaNumericClose(cNorm, oNorm) ? 220_000 : 0
        }

        let cLeft = cParts[0]
        let cRight = cParts[1]
        let oLeft = oParts[0]
        let oRight = oParts[1]
        var leftScore = 0
        if cLeft == oLeft {
            leftScore = 380_000
        } else if smallAlphaNumericClose(cLeft, oLeft) || cLeft.contains(oLeft) || oLeft.contains(cLeft) {
            leftScore = 260_000
        }
        var rightScore = 0
        if cRight == oRight {
            rightScore = 520_000
        } else if smallAlphaNumericClose(cRight, oRight) {
            rightScore = 360_000
        } else if cRight.hasPrefix(oRight) || oRight.hasPrefix(cRight) {
            rightScore = 240_000
        } else if numericCore(of: cRight) == numericCore(of: oRight) {
            rightScore = 330_000
        } else if strippedTrailingLetters(cRight) == strippedTrailingLetters(oRight) {
            rightScore = 280_000
        }

        if leftScore == 0 {
            // Do not let a near-miss numeric tail from the wrong set code survive the
            // card-number filter for same-name cards like Rob Lucci.
            if rightScore >= 520_000 { return 180_000 }
            return 0
        }

        return leftScore + rightScore
    }

    private static func normalizedOnePieceID(_ text: String) -> String {
        CardOCRFieldExtractor.normalizedOnePieceCollectorID(text)
    }

    private static func strippedTrailingLetters(_ text: String) -> String {
        text.replacingOccurrences(of: #"[A-Z]+$"#, with: "", options: .regularExpression)
    }

    private static func numericCore(of text: String) -> String {
        text.filter(\.isNumber)
    }

    private static func intEqual(_ a: String, _ b: String) -> Bool {
        if let ia = Int(a), let ib = Int(b) { return ia == ib }
        return a == b
    }

    private static func smallDigitStringClose(_ a: String, _ b: String) -> Bool {
        guard a != b else { return true }
        guard a.allSatisfy(\.isNumber), b.allSatisfy(\.isNumber) else { return false }
        guard a.count <= 4, b.count <= 4 else { return false }
        if a.count == b.count { return zip(a, b).filter { $0 != $1 }.count <= 1 }
        return editDistanceAtMostOne(a, b)
    }

    private static func smallAlphaNumericClose(_ a: String, _ b: String) -> Bool {
        guard a != b else { return true }
        guard a.count <= 8, b.count <= 8 else { return false }
        if a.count == b.count { return zip(a, b).filter { $0 != $1 }.count <= 1 }
        return editDistanceAtMostOne(a, b)
    }

    private static func editDistanceAtMostOne(_ a: String, _ b: String) -> Bool {
        let (s, t) = a.count <= b.count ? (a, b) : (b, a)
        guard t.count - s.count <= 1 else { return false }
        var i = s.startIndex; var j = t.startIndex; var skipped = 0
        while i < s.endIndex && j < t.endIndex {
            if s[i] == t[j] {
                i = s.index(after: i); j = t.index(after: j)
            } else {
                skipped += 1
                if skipped > 1 { return false }
                if s.count == t.count { i = s.index(after: i); j = t.index(after: j) }
                else { j = t.index(after: j) }
            }
        }
        return skipped + s.distance(from: i, to: s.endIndex) + t.distance(from: j, to: t.endIndex) <= 1
    }
}

// MARK: - VNRectangleObservation → CardQuad

private extension VNRectangleObservation {
    func toCardQuad(imageWidth: Int, imageHeight: Int) -> CardQuad {
        let w = CGFloat(imageWidth); let h = CGFloat(imageHeight)
        func d(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }
        return CardQuad(topLeft: d(topLeft), topRight: d(topRight), bottomLeft: d(bottomLeft), bottomRight: d(bottomRight))
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
              let rawImage = UIImage(data: data),
              let cgImage = rawImage.normalizedCGImage() else {
            DispatchQueue.main.async { [weak self] in
                self?.isCapturing = false
                self?.lastErrorMessage = "Could not read photo data. Try again."
            }
            return
        }

        let scaledImage = UIImage(cgImage: cgImage)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isCapturing = false
            // Camera stays live — do NOT stop the session
            processStillImage(scaledImage)
        }
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    func normalizedCGImage(maxDimension: CGFloat = 2048) -> CGImage? {
        let scale = min(maxDimension / max(size.width, size.height), 1)
        let targetSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: targetSize)) }.cgImage
    }
}

// MARK: - CGImage crop helpers

private extension CGImage {
    func rotated90(clockwise: Bool) -> CGImage? {
        let size = CGSize(width: CGFloat(height), height: CGFloat(width))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            if clockwise {
                cg.translateBy(x: size.width, y: 0)
                cg.rotate(by: .pi / 2)
            } else {
                cg.translateBy(x: 0, y: size.height)
                cg.rotate(by: -.pi / 2)
            }
            cg.draw(self, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return image.cgImage
    }

    func rotated180() -> CGImage? {
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: size.width, y: size.height)
            cg.rotate(by: .pi)
            cg.draw(self, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return image.cgImage
    }

    /// Keeps the bottom `fraction` of the image (UIKit-style top-left origin in pixel space).
    func croppingToBottomFraction(_ fraction: CGFloat) -> CGImage? {
        guard fraction > 0, fraction <= 1 else { return nil }
        let fh = CGFloat(height) * fraction
        let y = CGFloat(height) - fh
        let r = CGRect(x: 0, y: y, width: CGFloat(width), height: fh).integral
        let inter = r.intersection(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard !inter.isEmpty else { return nil }
        return cropping(to: inter)
    }

    /// Keeps the vertical band between `start` and `end` measured from the physical top of the card.
    func croppingBetweenTopFractions(_ start: CGFloat, _ end: CGFloat) -> CGImage? {
        guard start >= 0, end <= 1, end > start else { return nil }
        let y = CGFloat(height) * start
        let h = CGFloat(height) * (end - start)
        let r = CGRect(x: 0, y: y, width: CGFloat(width), height: h).integral
        let inter = r.intersection(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard !inter.isEmpty else { return nil }
        return cropping(to: inter)
    }

    func croppedToCardRect(_ normalizedRect: CGRect, imageSize: CGSize) -> CGImage? {
        guard !normalizedRect.isEmpty else { return nil }
        let imgW = CGFloat(width); let imgH = CGFloat(height)
        let scaleX = imgW / imageSize.width; let scaleY = imgH / imageSize.height
        let fillScale = max(scaleX, scaleY)
        let offsetX = (imgW - imageSize.width * fillScale) / 2
        let offsetY = (imgH - imageSize.height * fillScale) / 2
        let cropX = offsetX + normalizedRect.minX * imageSize.width * fillScale
        let cropY = offsetY + normalizedRect.minY * imageSize.height * fillScale
        let cropW = normalizedRect.width * imageSize.width * fillScale
        let cropH = normalizedRect.height * imageSize.height * fillScale
        let pixelRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
            .intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard !pixelRect.isEmpty else { return nil }
        return cropping(to: pixelRect)
    }
}
