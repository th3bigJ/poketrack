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
    private var loadTask: Task<Void, Never>?
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

    func load(url: URL?, localURL: URL?, targetSize: CGSize?) {
        loadTask?.cancel()
        loadTask = nil

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

        let capturedURL = url
        let capturedLocal = localURL
        let capturedTarget = targetSize

        loadTask = Task.detached(priority: .utility) { [weak self] in
            let scale = await MainActor.run { UIScreen.main.scale }
            let key = Self.cacheKey(url: capturedURL, localURL: capturedLocal, targetSize: capturedTarget, scale: scale)

            if let memCached = await DecodedImageMemoryCache.shared.image(for: key) {
                await MainActor.run { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    guard self.currentURL == capturedURL else { return }
                    self.image = memCached
                    self.loadTask = nil
                }
                return
            }

            var decoded: UIImage?

            // Serve from offline pack if available
            if let localURL = capturedLocal, let data = try? Data(contentsOf: localURL) {
                decoded = ThumbnailImageDecode.downsampled(data: data, targetSize: capturedTarget, scale: scale)
            }

            if decoded == nil {
                let request = URLRequest(url: capturedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

                if let cached = AppURLSession.imageURLCache.cachedResponse(for: request) {
                    decoded = self?.decodeImage(from: cached, targetSize: capturedTarget, scale: scale)
                    if decoded == nil {
                        AppURLSession.imageURLCache.removeCachedResponse(for: request)
                    }
                }

                if decoded == nil {
                    do {
                        let refreshRequest = URLRequest(url: capturedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                        let (data, response) = try await AppURLSession.images.data(for: refreshRequest)
                        guard !Task.isCancelled else { return }
                        let cachedResponse = CachedURLResponse(response: response, data: data)
                        if self?.decodeImage(from: cachedResponse, targetSize: capturedTarget, scale: scale) != nil {
                            AppURLSession.imageURLCache.storeCachedResponse(cachedResponse, for: request)
                        } else {
                            AppURLSession.imageURLCache.removeCachedResponse(for: request)
                        }
                        decoded = self?.decodeImage(from: cachedResponse, targetSize: capturedTarget, scale: scale)
                    } catch { }
                }
            }

            if let decoded {
                await DecodedImageMemoryCache.shared.set(decoded, for: key)
            }

            let finalImage = decoded
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                guard self.currentURL == capturedURL else { return }
                self.image = finalImage
                self.loadTask = nil
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
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
            } else {
                placeholder()
            }
        }
        .task(id: taskID) {
            loader.load(url: url, localURL: localURL, targetSize: targetSize)
        }
        .onDisappear {
            loader.cancel()
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

    init(url: URL?, targetSize: CGSize? = nil) {
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
            } else {
                Color.gray.opacity(0.12)
                    .aspectRatio(5 / 7, contentMode: .fit)
            }
        }
        .task(id: taskID) {
            loader.load(url: url, localURL: localURL, targetSize: targetSize)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}
