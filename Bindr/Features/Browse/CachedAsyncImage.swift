import SwiftUI
import UIKit

@Observable
private final class ImageLoader {
    var image: UIImage?
    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?
    private var targetSize: CGSize?

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
                decoded = ThumbnailImageDecode.downsampled(data: cached.data, targetSize: capturedTarget, scale: scale)
            } else {
                do {
                    let (data, response) = try await AppURLSession.images.data(for: request)
                    guard !Task.isCancelled else { return }
                    AppURLSession.imageURLCache.storeCachedResponse(
                        CachedURLResponse(response: response, data: data), for: request)
                    decoded = ThumbnailImageDecode.downsampled(data: data, targetSize: capturedTarget, scale: scale)
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
            if let ui = loader.image {
                content(Image(uiImage: ui))
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: loader.image != nil)
        .task(id: url?.absoluteString ?? "") {
            loader.load(url: url, targetSize: targetSize)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}
