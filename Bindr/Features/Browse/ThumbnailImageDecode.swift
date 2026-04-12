import ImageIO
import UIKit

/// Decode path safe for background threads — pass `scale` explicitly (no `UIScreen` on worker threads).
enum ThumbnailImageDecode {
    static func downsampled(data: Data, targetSize: CGSize?, scale: CGFloat) -> UIImage? {
        guard let targetSize = targetSize, targetSize.width > 0, targetSize.height > 0 else {
            return UIImage(data: data)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetSize.width, targetSize.height) * scale
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
