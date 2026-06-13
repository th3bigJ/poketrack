import SwiftUI

/// Set logos from R2 with candidate URL fallback.
struct SetLogoAsyncImage: View {
    let logoSrc: String
    let height: CGFloat
    let brand: TCGBrand

    private var trimmed: String {
        logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urls: [URL] {
        guard !trimmed.isEmpty else { return [] }
        return AppConfiguration.setLogoURLCandidates(logoSrc: trimmed)
    }

    private var primaryURL: URL? {
        urls.first
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                Color.clear
            } else {
                CachedAsyncImage(
                    url: primaryURL,
                    targetSize: BindrImageSizing.squareLogo(side: height)
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }
}

/// Set rarity / expansion symbol from `sets.json` `symbolSrc`.
struct SetSymbolAsyncImage: View {
    let symbolSrc: String
    let height: CGFloat
    let brand: TCGBrand

    @State private var loader = SetSymbolImageLoader()

    private var trimmed: String {
        symbolSrc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urls: [URL] {
        guard !trimmed.isEmpty else { return [] }
        return AppConfiguration.setSymbolURLCandidates(symbolSrc: trimmed)
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                Color.clear
            } else if let ui = loader.image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .bindrRasterizedForDisplay()
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .task(id: trimmed) {
            await loader.load(urls: urls, targetSize: BindrImageSizing.squareLogo(side: height))
        }
    }
}

@Observable
private final class SetSymbolImageLoader {
    var image: UIImage?

    func load(urls: [URL], targetSize: CGSize) async {
        image = nil
        guard !urls.isEmpty else { return }

        let scale = await MainActor.run { UIScreen.main.scale }

        for url in urls {
            guard !Task.isCancelled else { return }

            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            var data: Data?

            if let cached = AppURLSession.imageURLCache.cachedResponse(for: request) {
                data = cached.data
            } else {
                data = try? await AppURLSession.images.data(for: request).0
            }

            guard let data,
                  let decoded = ThumbnailImageDecode.downsampled(data: data, targetSize: targetSize, scale: scale)
            else { continue }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.image = decoded
            }
            return
        }
    }
}
