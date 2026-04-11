import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision
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

    /// Fires the still photo pipeline manually.
    func capturePhoto() {
        guard session.isRunning, !isCapturing else { return }
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
                if let conn = self.videoOutput.connection(with: .video), conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
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
        let ocrCGImage = preprocessCardForOCR(croppedCG) ?? croppedCG
        let request = VNRecognizeTextRequest { [weak self] req, _ in
            self?.handleTextObservations(
                req.results as? [VNRecognizedTextObservation] ?? []
            )
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: ocrCGImage, orientation: .up, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.scanState = .idle
                    self?.lastErrorMessage = "Text recognition failed. Try better light or retake."
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

    private func mixedFallbackPool(
        service: CardDataService, cleanedName: String?, hp: String?,
        setNumber: String?, illustrator: String?, centerHint: String?
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
        var deduped = Self.dedupCards(combined)
        if let hp, let ocrHP = Int(hp.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let exactHP = deduped.filter { $0.hp == nil || $0.hp == ocrHP }
            if !exactHP.isEmpty { deduped = exactHP }
        }
        return deduped
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

        let rawName = cardName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = Self.cleanedOCRName(rawName)
        let hasName = !(rawName?.isEmpty ?? true)

        var pool: [Card]
        if hasName {
            pool = await service.searchByName(query: rawName!)
            if pool.isEmpty, let cleanedName, cleanedName.caseInsensitiveCompare(rawName!) != .orderedSame {
                pool = await service.searchByName(query: cleanedName)
            }
            if pool.isEmpty, let cleanedName {
                pool = await service.search(query: cleanedName)
                if pool.isEmpty { pool = await service.searchSoftTokenMatch(query: cleanedName) }
            }
        } else if let hint = centerHint, !hint.isEmpty {
            pool = await service.search(query: hint)
            if pool.isEmpty { pool = await service.searchSoftTokenMatch(query: hint) }
        } else {
            pool = []
        }

        if pool.isEmpty {
            pool = await mixedFallbackPool(
                service: service, cleanedName: cleanedName, hp: hp,
                setNumber: setNumber, illustrator: illustrator, centerHint: centerHint
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
        guard !isAnalysingFrame else { return }
        guard Date().timeIntervalSince(lastAutoCaptureTime) >= autoCaptureMinInterval else { return }

        isAnalysingFrame = true
        defer { isAnalysingFrame = false }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Pass the buffer directly to Vision. Orientation must match AVCaptureConnection.videoOrientation
        // (set to portrait in setup) so bounding boxes line up with the on-screen reticle.
        let visionOrientation = Self.cgImageOrientation(forVideoOrientation: connection.videoOrientation)
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
            ? CGRect(x: 0.14, y: 0.14, width: 0.72, height: 0.72)
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

    /// Maps `AVCaptureVideoOrientation` to the `CGImagePropertyOrientation` Vision expects for the
    /// same preview rotation. See “Displaying camera content” / matching preview to still analysis.
    private static func cgImageOrientation(forVideoOrientation o: AVCaptureVideoOrientation) -> CGImagePropertyOrientation {
        switch o {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeRight: return .up
        case .landscapeLeft: return .down
        @unknown default: return .right
        }
    }

    /// Converts a normalized UIKit rect (origin top-left, y down) into Vision’s normalized space
    /// (origin bottom-left, y up) for the same `CGImagePropertyOrientation` passed to `VNImageRequestHandler`.
    ///
    /// For `.right` (typical back camera + portrait `videoOrientation`), this matches the reticle mapping
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
