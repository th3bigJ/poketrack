import SwiftUI
import UIKit

/// Loads a low-resolution image immediately, then progressively loads and crossfades to high-resolution.
/// Provides a premium, perceived-instant loading experience.
@Observable
private final class ProgressiveImageLoader {
    enum LoadState {
        case idle
        case loadingLow
        case lowReady(UIImage)
        case loadingHigh(UIImage)  // low-res visible while high loads
        case highReady(UIImage)
        case failed
    }

    var state: LoadState = .idle

    var readyImage: UIImage? {
        switch state {
        case .lowReady(let img), .loadingHigh(let img), .highReady(let img): return img
        default: return nil
        }
    }

    private var loadTask: Task<Void, Never>?
    private var currentLowURL: URL?
    private var currentHighURL: URL?

    private static func cacheKey(url: URL, scale: CGFloat) -> String {
        "\(url.absoluteString)|full|@\(scale)"
    }

    func load(lowResURL: URL?, highResURL: URL?, localLowResURL: URL? = nil) {
        loadTask?.cancel()

        // Skip reload only when URLs match, we already have an image, AND there's no local
        // file to try — if localLowResURL is provided we always reload to serve from disk.
        if lowResURL == currentLowURL && highResURL == currentHighURL && localLowResURL == nil {
            switch state {
            case .lowReady, .loadingHigh, .highReady:
                return
            default:
                break
            }
        }

        currentLowURL = lowResURL
        currentHighURL = highResURL

        let capturedLow = lowResURL
        let capturedHigh = highResURL
        let capturedLocalLow = localLowResURL

        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runProgressiveLoad(lowResURL: capturedLow, highResURL: capturedHigh, localLowResURL: capturedLocalLow)
        }
    }

    private func runProgressiveLoad(lowResURL: URL?, highResURL: URL?, localLowResURL: URL?) async {
        let scale = await MainActor.run { UIScreen.main.scale }
        if let highURL = highResURL {
            let key = Self.cacheKey(url: highURL, scale: scale)
            if let cached = await DecodedImageMemoryCache.shared.image(for: key) {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .highReady(cached)
                }
                return
            }
        }
        // Check cache for high-res first (avoids low→high flash when already cached)
        if let highURL = highResURL {
            let highRequest = URLRequest(url: highURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = AppURLSession.imageURLCache.cachedResponse(for: highRequest),
               let ui = UIImage(data: cached.data) {
                let key = Self.cacheKey(url: highURL, scale: scale)
                await DecodedImageMemoryCache.shared.set(ui, for: key)
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .highReady(ui)
                }
                return
            }
        }

        // Serve low-res from offline pack if available
        if let localURL = localLowResURL, let data = try? Data(contentsOf: localURL), let ui = UIImage(data: data) {
            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.state = .loadingHigh(ui)
            }
            if let high = highResURL {
                await loadHighResAsync(high)
            } else {
                if let low = lowResURL {
                    let key = Self.cacheKey(url: low, scale: scale)
                    await DecodedImageMemoryCache.shared.set(ui, for: key)
                }
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .highReady(ui)
                }
            }
            return
        }

        if let lowURL = lowResURL {
            let lowRequest = URLRequest(url: lowURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = AppURLSession.imageURLCache.cachedResponse(for: lowRequest),
               let ui = UIImage(data: cached.data) {
                let key = Self.cacheKey(url: lowURL, scale: scale)
                await DecodedImageMemoryCache.shared.set(ui, for: key)
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .loadingHigh(ui)
                }
                if let high = highResURL {
                    await loadHighResAsync(high)
                } else {
                    await MainActor.run { [weak self] in
                        guard !Task.isCancelled else { return }
                        self?.state = .highReady(ui)
                    }
                }
                return
            }
        }

        await MainActor.run { [weak self] in
            guard !Task.isCancelled else { return }
            self?.state = .loadingLow
        }
        await loadLowResAsync(lowResURL, thenLoadHigh: highResURL)
    }

    private func loadLowResAsync(_ url: URL?, thenLoadHigh highURL: URL?) async {
        guard let url else {
            await loadHighResAsync(highURL)
            return
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

        do {
            let (data, response) = try await AppURLSession.images.data(for: request)
            guard !Task.isCancelled else { return }

            AppURLSession.imageURLCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data), for: request)

            guard let ui = UIImage(data: data) else {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .failed
                }
                return
            }
            let scale = await MainActor.run { UIScreen.main.scale }
            let key = Self.cacheKey(url: url, scale: scale)
            await DecodedImageMemoryCache.shared.set(ui, for: key)

            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.state = .loadingHigh(ui)
            }

            if let highURL = highURL, highURL != url {
                await loadHighResAsync(highURL)
            } else {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .highReady(ui)
                }
            }
        } catch {
            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.state = .failed
            }
        }
    }

    private func loadHighResAsync(_ url: URL?) async {
        guard let url else { return }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

        do {
            let (data, response) = try await AppURLSession.images.data(for: request)
            guard !Task.isCancelled else { return }

            AppURLSession.imageURLCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data), for: request)

            if let ui = UIImage(data: data) {
                let scale = await MainActor.run { UIScreen.main.scale }
                let key = Self.cacheKey(url: url, scale: scale)
                await DecodedImageMemoryCache.shared.set(ui, for: key)
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .highReady(ui)
                }
            }
        } catch { }
    }

    func cancel() {
        loadTask?.cancel()
    }
}

/// Progressive image view that shows low-res immediately, then smoothly crossfades to high-res.
/// Use this for detail views where image quality matters and perceived performance is critical.
/// When offline mode is active the low-res is served from the local pack; hi-res is always fetched from R2.
struct ProgressiveAsyncImage<Placeholder: View>: View {
    let lowResURL: URL?
    let highResURL: URL?
    let onImageLoaded: ((UIImage) -> Void)?
    let placeholder: () -> Placeholder

    @State private var loader = ProgressiveImageLoader()
    @Environment(\.offlineImageContext) private var offlineContext

    init(
        lowResURL: URL?,
        highResURL: URL? = nil,
        onImageLoaded: ((UIImage) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.lowResURL = lowResURL
        self.highResURL = highResURL
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder
    }

    private var localLowResURL: URL? {
        guard let lowResURL else { return nil }
        return offlineContext?.localURL(for: lowResURL)
    }

    var body: some View {
        Group {
            switch loader.state {
            case .idle, .loadingLow:
                placeholder()

            case .lowReady(let image), .loadingHigh(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))

            case .highReady(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            case .failed:
                placeholder()
            }
        }
        .onChange(of: loader.readyImage) { _, image in
            if let image { onImageLoaded?(image) }
        }
        .task(id: "\(lowResURL?.absoluteString ?? "")|\(highResURL?.absoluteString ?? "")|\(offlineContext?.isOfflineEnabled == true)|\(offlineContext?.packDataRevision ?? 0)") {
            loader.load(lowResURL: lowResURL, highResURL: highResURL, localLowResURL: localLowResURL)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

// MARK: - Optimized Cached Image with Downsampling

@Observable
private final class OptimizedImageLoader {
    var image: UIImage?
    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?
    private var targetSize: CGSize?

    func load(url: URL?, localURL: URL? = nil, targetSize: CGSize? = nil) {
        loadTask?.cancel()

        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        if url == currentURL, image != nil, localURL == nil { return }

        currentURL = url
        self.targetSize = targetSize
        image = nil

        let capturedURL = url
        let capturedLocal = localURL
        let capturedTarget = targetSize

        loadTask = Task.detached(priority: .utility) { [weak self] in
            let scale = await MainActor.run { UIScreen.main.scale }

            var decoded: UIImage?

            if let localURL = capturedLocal, let data = try? Data(contentsOf: localURL) {
                decoded = ThumbnailImageDecode.downsampled(data: data, targetSize: capturedTarget, scale: scale)
            }

            if decoded == nil {
                let request = URLRequest(url: capturedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
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
            }

            let finalImage = decoded
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                guard self.currentURL == capturedURL else { return }
                self.image = finalImage
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
    }
}

/// Enhanced cached image with optional downsampling for thumbnails.
/// Use this for grid cells where memory efficiency matters.
struct OptimizedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let targetSize: CGSize?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var loader = OptimizedImageLoader()
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
        .task(id: "\(url?.absoluteString ?? "")|\(offlineContext?.isOfflineEnabled == true)|\(offlineContext?.packDataRevision ?? 0)") {
            loader.load(url: url, localURL: localURL, targetSize: targetSize)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}
