import SwiftUI
import UIKit

extension UIImage {
    /// Samples vibrant mid-tone colors from card/sealed artwork for aura gradients.
    /// Expects sRGB-flattened images from ``ThumbnailImageDecode`` when possible.
    func bindrAuraColors(maxColors: Int) -> [Color] {
        guard maxColors > 0, let cgImage else { return [] }

        let sampleWidth = 44
        let sampleHeight = 62
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var raw = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &raw,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return [] }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        struct AuraBin: Hashable {
            let r: Int
            let g: Int
            let b: Int
        }

        var histogram: [AuraBin: Double] = [:]
        let step = 32.0

        for y in 0 ..< sampleHeight {
            for x in 0 ..< sampleWidth {
                let i = y * bytesPerRow + (x * bytesPerPixel)
                let r = Double(raw[i])
                let g = Double(raw[i + 1])
                let b = Double(raw[i + 2])
                let a = Double(raw[i + 3]) / 255.0
                guard a > 0.6 else { continue }

                let maxC = max(r, g, b) / 255.0
                let minC = min(r, g, b) / 255.0
                let delta = maxC - minC
                let saturation = maxC == 0 ? 0 : (delta / maxC)
                let brightness = maxC

                guard saturation >= 0.22 else { continue }
                guard brightness >= 0.18 && brightness <= 0.94 else { continue }

                let weight = 0.3 + saturation * 1.6 + brightness * 0.2
                histogram[AuraBin(r: Int(floor(r / step)), g: Int(floor(g / step)), b: Int(floor(b / step))), default: 0] += weight
            }
        }

        let sortedBins = histogram.sorted { $0.value > $1.value }.map(\.key)
        guard !sortedBins.isEmpty else { return [] }

        var selected: [SIMD3<Double>] = []

        for bin in sortedBins {
            let candidate = SIMD3<Double>(
                (Double(bin.r) + 0.5) * step / 255.0,
                (Double(bin.g) + 0.5) * step / 255.0,
                (Double(bin.b) + 0.5) * step / 255.0
            )

            let isDistinct = selected.allSatisfy { existing in
                let delta = candidate - existing
                return sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z) > 0.22
            }
            guard isDistinct else { continue }
            selected.append(candidate)
            if selected.count == maxColors { break }
        }

        if selected.isEmpty, let first = sortedBins.first {
            selected = [
                SIMD3<Double>(
                    (Double(first.r) + 0.5) * step / 255.0,
                    (Double(first.g) + 0.5) * step / 255.0,
                    (Double(first.b) + 0.5) * step / 255.0
                )
            ]
        }

        if selected.count == 1, let first = selected.first {
            selected += [first * 0.86, first * 0.72]
        } else if selected.count == 2 {
            selected.append(selected[1] * 0.7 + selected[0] * 0.3)
        }

        return selected.map { Color(red: $0.x, green: $0.y, blue: $0.z) }
    }
}
