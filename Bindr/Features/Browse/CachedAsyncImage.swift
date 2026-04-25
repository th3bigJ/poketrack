import SwiftUI
import UIKit

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

    func load(url: URL?, targetSize: CGSize?) {
        loadTask?.cancel()
        loadTask = nil

        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        if url == currentURL {
            if image != nil { return }
        }

        currentURL = url
        self.targetSize = targetSize
        image = nil

        let capturedURL = url
        let capturedTarget = targetSize

        loadTask = Task.detached(priority: .utility) { [weak self] in
            let scale = await MainActor.run { UIScreen.main.scale }
            let request = URLRequest(url: capturedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

            var decoded: UIImage?

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
        .task(id: url?.absoluteString ?? "") {
            loader.load(url: url, targetSize: targetSize)
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

    init(url: URL?, targetSize: CGSize? = nil) {
        self.url = url
        self.targetSize = targetSize
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
            } else {
                Color.gray.opacity(0.12)
                    .aspectRatio(5 / 7, contentMode: .fit)
            }
        }
        .task(id: url?.absoluteString ?? "") {
            loader.load(url: url, targetSize: targetSize)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}
