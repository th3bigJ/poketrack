import SwiftUI

@Observable
private final class ImageLoader {
    var image: UIImage?
    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?
    private var targetSize: CGSize?

    func load(url: URL?, targetSize: CGSize? = nil) {
        loadTask?.cancel()

        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        // Skip only when this URL already produced a decoded image; if `image` is nil, reload (e.g. after `.task` cancellation).
        if url == currentURL, image != nil { return }

        currentURL = url
        self.targetSize = targetSize
        image = nil

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

        if let cached = URLCache.shared.cachedResponse(for: request) {
            // Decode on background thread with optional downsampling
            loadTask = Task.detached(priority: .userInitiated) { [weak self] in
                let decoded = self?.decodeWithDownsampling(data: cached.data, targetSize: targetSize)
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.image = decoded
                }
            }
            return
        }

        loadTask = Task { [weak self] in
            do {
                let (data, response) = try await AppURLSession.images.data(for: request)
                guard !Task.isCancelled else { return }
                
                URLCache.shared.storeCachedResponse(
                    CachedURLResponse(response: response, data: data), for: request)
                
                // Decode with downsampling on background
                let decoded = self?.decodeWithDownsampling(data: data, targetSize: targetSize)
                
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.image = decoded
                }
            } catch { }
        }
    }

    /// Decode image with optional downsampling to reduce memory usage
    private func decodeWithDownsampling(data: Data, targetSize: CGSize?) -> UIImage? {
        guard let targetSize = targetSize, targetSize.width > 0, targetSize.height > 0 else {
            return UIImage(data: data)
        }

        // Use ImageIO for efficient downsampling
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetSize.width, targetSize.height) * UIScreen.main.scale
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
    }

    func cancel() {
        loadTask?.cancel()
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
        .task(id: url) {
            loader.load(url: url, targetSize: targetSize)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}
