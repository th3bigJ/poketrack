import UIKit
import Vision

enum TextRecognition {
    static func strings(from image: UIImage) throws -> [String] {
        guard let cg = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])
        guard let observations = request.results as? [VNRecognizedTextObservation] else { return [] }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
