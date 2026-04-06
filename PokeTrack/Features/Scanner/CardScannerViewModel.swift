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
    var extractedName: String? = nil
    var extractedHP: String? = nil
    var extractedSetNumber: String? = nil
    var searchQuery: String? = nil
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            debugInfo.rawOCRStrings = sortedDebug
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

        let query: String
        if let name = cardName, let number = setNumber {
            query = "\(name) \(number)"
        } else if let name = cardName {
            query = name
        } else if let number = setNumber {
            query = number
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.detectedText = nil
                self?.scanState = .idle
                self?.lastErrorMessage = "Could not read card name or number. Try again."
                self?.debugInfo.extractedName = nil
                self?.debugInfo.extractedHP = nil
                self?.debugInfo.extractedSetNumber = nil
                self?.debugInfo.searchQuery = nil
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var summary = [cardName, setNumber].compactMap { $0 }.joined(separator: " ")
            if let hp = fields.hp {
                summary += summary.isEmpty ? "HP \(hp)" : " · HP \(hp)"
            }
            detectedText = summary
            scanState = .scanning
            debugInfo.extractedName = cardName
            debugInfo.extractedHP = fields.hp
            debugInfo.extractedSetNumber = setNumber
            debugInfo.searchQuery = query
        }

        Task { [weak self] in
            await self?.runSearch(query: query, cardName: cardName, setNumber: setNumber)
        }
    }

    private func runSearch(query: String, cardName: String?, setNumber: String?) async {
        guard let service = cardDataService else {
            print("[Scanner] cardDataService is nil — was configure() called?")
            return
        }
        let results = await service.search(query: query)

        await MainActor.run { [weak self] in
            guard let self else { return }
            debugInfo.searchResultCount = results.count
            debugInfo.topResult = results.first.map { "\($0.cardName) [\($0.setCode) \($0.cardNumber)]" }
        }

        guard let top = results.first else {
            let alt = await fallbackMatches(
                service: service,
                cardName: cardName,
                setNumber: setNumber,
                primaryQuery: query
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                matchBuffer.removeAll()
                searchResults = []
                alternativeMatches = alt
                debugInfo.matchBufferState = alt.isEmpty ? "no results — buffer cleared" : "fallback: \(alt.count) candidate(s)"
                scanState = .idle
                if alt.isEmpty {
                    lastErrorMessage = "No catalog match for that text. Try Retake."
                } else {
                    lastErrorMessage = "No exact match — try “Show possible matches” below."
                }
            }
            return
        }

        await MainActor.run { [weak self] in
            guard let self else { return }
            let count = (matchBuffer[top.masterCardId] ?? 0) + 1
            matchBuffer = [top.masterCardId: count]
            debugInfo.matchBufferState = "\(top.cardName): \(count)/\(matchThreshold)"

            if count >= matchThreshold {
                searchResults = Array(results.prefix(maxMatchesToShow))
                alternativeMatches = []
                scanState = .found(top)
                matchBuffer.removeAll()
                lastErrorMessage = nil
            }
        }
    }

    /// Extra searches when OCR/query is noisy (e.g. `162/193` vs `062/193`).
    private func fallbackMatches(
        service: CardDataService,
        cardName: String?,
        setNumber: String?,
        primaryQuery: String
    ) async -> [Card] {
        var queries: [String] = []
        if let name = cardName, !name.isEmpty { queries.append(name) }
        if let sn = setNumber, !sn.isEmpty {
            queries.append(sn)
            for variant in setNumberVariants(sn) {
                queries.append(variant)
                if let name = cardName, !name.isEmpty {
                    queries.append("\(name) \(variant)")
                }
            }
        }
        if !primaryQuery.isEmpty { queries.append(primaryQuery) }

        var seen = Set<String>()
        var out: [Card] = []
        for q in queries {
            let r = await service.search(query: q)
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
