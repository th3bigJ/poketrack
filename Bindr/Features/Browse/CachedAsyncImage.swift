import SwiftUI
import UIKit

actor DecodedImageMemoryCache {
    static let shared = DecodedImageMemoryCache()
    private var storage: [String: UIImage] = [:]
    private let maxEntries = 1200

    func image(for key: String) -> UIImage? {
        storage[key]
    }

    func set(_ image: UIImage, for key: String) {
        storage[key] = image
        if storage.count > maxEntries, let keyToRemove = storage.keys.first {
            storage.removeValue(forKey: keyToRemove)
        }
    }
}

@Observable
private final class ImageLoader {
    var image: UIImage?
    private var currentURL: URL?
    private var targetSize: CGSize?

    private func decodeImage(from cached: CachedURLResponse, targetSize: CGSize?, scale: CGFloat) -> UIImage? {
        if let http = cached.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            return nil
        }
        return ThumbnailImageDecode.downsampled(data: cached.data, targetSize: targetSize, scale: scale)
    }

    private static func cacheKey(url: URL, localURL: URL?, targetSize: CGSize?, scale: CGFloat) -> String {
        let source = localURL?.path(percentEncoded: false) ?? url.absoluteString
        let w = targetSize?.width ?? 0
        let h = targetSize?.height ?? 0
        return "\(source)|\(w)x\(h)|@\(scale)"
    }

    func load(url: URL?, localURL: URL?, targetSize: CGSize?) async {
        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        // Only skip if URL is the same AND we have no local file to try.
        // If localURL is provided (offline pack), always reload so we serve from disk.
        if url == currentURL, image != nil, localURL == nil {
            return
        }

        currentURL = url
        self.targetSize = targetSize
        image = nil

        let scale = await MainActor.run { UIScreen.main.scale }
        let key = Self.cacheKey(url: url, localURL: localURL, targetSize: targetSize, scale: scale)

        if let memCached = await DecodedImageMemoryCache.shared.image(for: key) {
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                guard self.currentURL == url else { return }
                self.image = memCached
            }
            return
        }

        var decoded: UIImage?

        // Serve from offline pack if available
        if let localURL = localURL, let data = try? Data(contentsOf: localURL) {
            decoded = ThumbnailImageDecode.downsampled(data: data, targetSize: targetSize, scale: scale)
        }

        if decoded == nil {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

            if let cached = AppURLSession.imageURLCache.cachedResponse(for: request) {
                decoded = decodeImage(from: cached, targetSize: targetSize, scale: scale)
                if decoded == nil {
                    AppURLSession.imageURLCache.removeCachedResponse(for: request)
                }
            }

            if decoded == nil {
                do {
                    let refreshRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                    let (data, response) = try await AppURLSession.images.data(for: refreshRequest)
                    guard !Task.isCancelled else { return }
                    let cachedResponse = CachedURLResponse(response: response, data: data)
                    if decodeImage(from: cachedResponse, targetSize: targetSize, scale: scale) != nil {
                        AppURLSession.imageURLCache.storeCachedResponse(cachedResponse, for: request)
                    } else {
                        AppURLSession.imageURLCache.removeCachedResponse(for: request)
                    }
                    decoded = decodeImage(from: cachedResponse, targetSize: targetSize, scale: scale)
                } catch { }
            }
        }

        if let decoded {
            await DecodedImageMemoryCache.shared.set(decoded, for: key)
        }

        let finalImage = decoded
        await MainActor.run { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard self.currentURL == url else { return }
            self.image = finalImage
        }
    }
}

/// Drop-in for `AsyncImage` backed by `URLCache` with optional downsampling.
/// Reliable in `LazyVGrid` and memory-efficient for thumbnails.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let targetSize: CGSize?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var loader = ImageLoader()
    @Environment(\.offlineImageContext) private var offlineContext

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.content = content
        self.placeholder = placeholder
    }

    private var localURL: URL? {
        guard let url else { return nil }
        return offlineContext?.localURL(for: url)
    }

    private var taskID: String {
        "\(url?.absoluteString ?? "")|\(offlineContext?.isOfflineEnabled == true)|\(offlineContext?.packDataRevision ?? 0)"
    }

    var body: some View {
        Group {
            if let ui = loader.image,
               ui.size.width.isFinite,
               ui.size.height.isFinite,
               ui.size.width > 0,
               ui.size.height > 0 {
                content(Image(uiImage: ui))
                    .bindrRasterizedForDisplay()
            } else {
                placeholder()
            }
        }
        .task(id: taskID) {
            await loader.load(url: url, localURL: localURL, targetSize: targetSize)
        }
    }
}

/// Environment-free thumbnail for card grids.
/// iOS 26 corrupts the attribute graph when `@Environment` is read during
/// `ForEach` / dynamic-container update passes (see `CardGridCell`).
struct GridCardThumbnailImage: View {
    private let url: URL?
    private let localURL: URL?
    private let reloadToken: String
    private let targetSize: CGSize?

    @State private var loader = ImageLoader()

    init(
        url: URL?,
        localURL: URL? = nil,
        reloadToken: String = "",
        targetSize: CGSize? = BindrImageSizing.cardGridThumbnail
    ) {
        self.url = url
        self.localURL = localURL
        self.reloadToken = reloadToken
        self.targetSize = targetSize
    }

    private var taskID: String {
        "\(url?.absoluteString ?? "")|\(reloadToken)"
    }

    private var hasRenderableImage: Bool {
        guard let ui = loader.image else { return false }
        guard ui.size.width.isFinite, ui.size.height.isFinite else { return false }
        guard ui.size.width > 0, ui.size.height > 0 else { return false }
        if let cg = ui.cgImage {
            guard cg.width > 0, cg.height > 0 else { return false }
        }
        return true
    }

    var body: some View {
        Group {
            if hasRenderableImage, let ui = loader.image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .bindrRasterizedForDisplay()
            } else {
                Color.gray.opacity(0.12)
                    .aspectRatio(5 / 7, contentMode: .fit)
            }
        }
        .task(id: taskID) {
            await loader.load(url: url, localURL: localURL, targetSize: targetSize)
        }
    }
}

/// Stable, non-generic thumbnail loader for card grids.
/// Avoids closure-based image rendering in high-churn LazyVGrid paths.
struct CachedCardThumbnailImage: View {
    private let url: URL?
    private let targetSize: CGSize?
    @State private var loader = ImageLoader()
    @Environment(\.offlineImageContext) private var offlineContext

    init(url: URL?, targetSize: CGSize? = BindrImageSizing.cardGridThumbnail) {
        self.url = url
        self.targetSize = targetSize
    }

    private var localURL: URL? {
        guard let url else { return nil }
        return offlineContext?.localURL(for: url)
    }

    private var hasRenderableImage: Bool {
        guard let ui = loader.image else { return false }
        guard ui.size.width.isFinite, ui.size.height.isFinite else { return false }
        guard ui.size.width > 0, ui.size.height > 0 else { return false }
        if let cg = ui.cgImage {
            guard cg.width > 0, cg.height > 0 else { return false }
        }
        return true
    }

    private var taskID: String {
        "\(url?.absoluteString ?? "")|\(offlineContext?.isOfflineEnabled == true)|\(offlineContext?.packDataRevision ?? 0)"
    }

    var body: some View {
        Group {
            if hasRenderableImage, let ui = loader.image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .bindrRasterizedForDisplay()
            } else {
                Color.gray.opacity(0.12)
                    .aspectRatio(5 / 7, contentMode: .fit)
            }
        }
        .task(id: taskID) {
            await loader.load(url: url, localURL: localURL, targetSize: targetSize)
        }
    }
}
