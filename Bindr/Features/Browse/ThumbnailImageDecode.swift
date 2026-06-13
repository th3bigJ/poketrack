import ImageIO
import UIKit

enum BindrImageSizing {
    /// Default downsample target for card grid thumbnails (~180pt @ 1x).
    static let cardGridThumbnail = CGSize(width: 180, height: 252)
    /// Feed / social compact card tile (~54pt wide @ 1x).
    static let compactCardThumbnail = CGSize(width: 54, height: 76)
    /// Set logo / symbol strip height-matched square.
    static func squareLogo(side: CGFloat) -> CGSize {
        CGSize(width: side, height: side)
    }
    /// Max long edge for detail / progressive images (enough for Retina without decoding poster-sized JPEGs).
    static let detailMaxPixelSize: CGFloat = 1200
}

/// Decode path safe for background threads — pass `scale` explicitly (no `UIScreen` on worker threads).
///
/// Prefers ImageIO thumbnails in sRGB/generic RGB without an embedded ICC profile.
/// Only re-draws through a bitmap context when the source carries a wide-gamut or ICC-tagged profile.
enum ThumbnailImageDecode {
    static func downsampled(data: Data, targetSize: CGSize?, scale: CGFloat) -> UIImage? {
        if let targetSize, targetSize.width > 0, targetSize.height > 0 {
            return decoded(data: data, maxPixelSize: max(targetSize.width, targetSize.height) * scale, scale: scale)
        }
        return decodedForDisplay(data: data, scale: scale)
    }

    static func decodedForDisplay(data: Data, scale: CGFloat) -> UIImage? {
        decoded(data: data, maxPixelSize: BindrImageSizing.detailMaxPixelSize, scale: scale)
    }

    private static func decoded(data: Data, maxPixelSize: CGFloat, scale: CGFloat) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              cgImage.width > 0,
              cgImage.height > 0
        else { return nil }

        let displayReady = normalizedForDisplay(cgImage) ?? cgImage
        let image = UIImage(cgImage: displayReady, scale: scale, orientation: .up)
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }

    /// Returns a copy safe for repeated SwiftUI compositing, flattening only when ICC / wide gamut is present.
    private static func normalizedForDisplay(_ image: CGImage) -> CGImage? {
        if isDisplaySafe(image) {
            return image.copy()
        }
        return flattenToSRGB(image)
    }

    /// Untagged sRGB — no extra ColorSync flatten pass needed.
    private static func isDisplaySafe(_ image: CGImage) -> Bool {
        guard let space = image.colorSpace else { return false }
        guard space.name == CGColorSpace.sRGB else { return false }
        return space.copyICCData() == nil
    }

    /// Last resort for Display P3 / ICC-tagged sources — one managed draw at decode time (then cached).
    private static func flattenToSRGB(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
