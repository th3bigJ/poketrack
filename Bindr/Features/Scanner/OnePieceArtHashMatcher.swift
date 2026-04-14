import Foundation
import ImageIO
import UIKit

struct OnePieceArtHashRerankResult {
    struct Match {
        let card: Card
        let distance: Int
    }

    let ranked: [Card]
    let matches: [Match]
}

actor OnePieceArtHashMatcher {
    static let shared = OnePieceArtHashMatcher()

    private var hashCache: [String: UInt64] = [:]

    func rerank(candidates: [Card], capturedImage: UIImage, maxCandidates: Int = 24) async -> OnePieceArtHashRerankResult? {
        let limited = Array(candidates.prefix(maxCandidates))
        guard limited.count >= 2 else { return nil }
        guard let capturedHash = Self.perceptualHash(for: capturedImage) else { return nil }

        var matches: [OnePieceArtHashRerankResult.Match] = []
        for card in limited {
            guard let cardHash = await catalogHash(for: card) else { continue }
            let distance = Self.hammingDistance(capturedHash, cardHash)
            matches.append(OnePieceArtHashRerankResult.Match(card: card, distance: distance))
        }

        guard matches.count >= 2 else { return nil }

        let originalIndex = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ($1.masterCardId, $0) })
        let sortedMatches = matches.sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return (originalIndex[lhs.card.masterCardId] ?? .max) < (originalIndex[rhs.card.masterCardId] ?? .max)
        }

        let matchedIDs = Set(sortedMatches.map { $0.card.masterCardId })
        let unmatched = candidates.filter { !matchedIDs.contains($0.masterCardId) }
        let ranked = sortedMatches.map { $0.card } + unmatched
        return OnePieceArtHashRerankResult(ranked: ranked, matches: sortedMatches)
    }

    private func catalogHash(for card: Card) async -> UInt64? {
        let cacheKey = card.masterCardId
        if let cached = hashCache[cacheKey] { return cached }

        let path = card.imageHighSrc ?? card.imageLowSrc
        let url = AppConfiguration.imageURL(relativePath: path)
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

        let data: Data?
        if let cached = AppURLSession.imageURLCache.cachedResponse(for: request) {
            data = cached.data
        } else {
            do {
                let (fetched, response) = try await AppURLSession.images.data(for: request)
                AppURLSession.imageURLCache.storeCachedResponse(
                    CachedURLResponse(response: response, data: fetched),
                    for: request
                )
                data = fetched
            } catch {
                data = nil
            }
        }

        guard let data, let hash = Self.perceptualHash(forImageData: data) else { return nil }
        hashCache[cacheKey] = hash
        return hash
    }

    private static func perceptualHash(for image: UIImage) -> UInt64? {
        if let cgImage = image.cgImage {
            return perceptualHash(for: cgImage)
        }
        guard let data = image.pngData() else { return nil }
        return perceptualHash(forImageData: data)
    }

    private static func perceptualHash(forImageData data: Data) -> UInt64? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return perceptualHash(for: cgImage)
    }

    private static func perceptualHash(for cgImage: CGImage) -> UInt64? {
        let cropRect = centralCropRect(width: cgImage.width, height: cgImage.height)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let left = pixels[y * width + x]
                let right = pixels[y * width + x + 1]
                hash <<= 1
                if left < right { hash |= 1 }
            }
        }
        return hash
    }

    private static func centralCropRect(width: Int, height: Int) -> CGRect {
        let insetX = Int(Double(width) * 0.06)
        let insetY = Int(Double(height) * 0.06)
        let rect = CGRect(
            x: insetX,
            y: insetY,
            width: max(1, width - insetX * 2),
            height: max(1, height - insetY * 2)
        )
        return rect.integral
    }

    private static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        Int((lhs ^ rhs).nonzeroBitCount)
    }
}
