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

    private var currentLowURL: URL?
    private var currentHighURL: URL?

    private static func cacheKey(url: URL, scale: CGFloat) -> String {
        "\(url.absoluteString)|full|@\(scale)"
    }

    private static func decode(data: Data, scale: CGFloat, maxPixelSize: CGFloat) -> UIImage? {
        ThumbnailImageDecode.downsampled(
            data: data,
            targetSize: CGSize(width: maxPixelSize, height: maxPixelSize),
            scale: scale
        )
    }

    func load(lowResURL: URL?, highResURL: URL?, localLowResURL: URL? = nil) async {
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

        await runProgressiveLoad(lowResURL: lowResURL, highResURL: highResURL, localLowResURL: localLowResURL)
    }

    private func runProgressiveLoad(lowResURL: URL?, highResURL: URL?, localLowResURL: URL?) async {
        let scale = await MainActor.run { UIScreen.main.scale }
        if let highURL = highResURL {
            let key = Self.cacheKey(url: highURL, scale: scale)
            if let cached = await DecodedImageMemoryCache.shared.image(for: key) {
                await MainActor.run { [weak self] in
                    guard self?.currentHighURL == highURL else { return }
                    self?.state = .highReady(cached)
                }
                return
            }
        }
        // Check cache for high-res first (avoids low→high flash when already cached)
        if let highURL = highResURL {
            let highRequest = URLRequest(url: highURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = AppURLSession.imageURLCache.cachedResponse(for: highRequest),
               let ui = Self.decode(data: cached.data, scale: scale, maxPixelSize: BindrImageSizing.detailMaxPixelSize) {
                let key = Self.cacheKey(url: highURL, scale: scale)
                await DecodedImageMemoryCache.shared.set(ui, for: key)
                await MainActor.run { [weak self] in
                    guard self?.currentHighURL == highURL else { return }
                    self?.state = .highReady(ui)
                }
                return
            }
        }

        // Serve low-res from offline pack if available
        if let localURL = localLowResURL, let data = try? Data(contentsOf: localURL),
           let ui = Self.decode(data: data, scale: scale, maxPixelSize: BindrImageSizing.detailMaxPixelSize) {
            await MainActor.run { [weak self] in
                guard self?.currentLowURL == lowResURL else { return }
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
                    guard self?.currentLowURL == lowResURL else { return }
                    self?.state = .highReady(ui)
                }
            }
            return
        }

        if let lowURL = lowResURL {
            let lowRequest = URLRequest(url: lowURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = AppURLSession.imageURLCache.cachedResponse(for: lowRequest),
               let ui = Self.decode(data: cached.data, scale: scale, maxPixelSize: BindrImageSizing.detailMaxPixelSize) {
                let key = Self.cacheKey(url: lowURL, scale: scale)
                await DecodedImageMemoryCache.shared.set(ui, for: key)
                await MainActor.run { [weak self] in
                    guard self?.currentLowURL == lowURL else { return }
                    self?.state = .loadingHigh(ui)
                }
                if let high = highResURL {
                    await loadHighResAsync(high)
                } else {
                    await MainActor.run { [weak self] in
                        guard self?.currentLowURL == lowURL else { return }
                        self?.state = .highReady(ui)
                    }
                }
                return
            }
        }

        await MainActor.run { [weak self] in
            guard !Task.isCancelled else { return }
            guard self?.currentLowURL == lowResURL else { return }
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
        let scale = await MainActor.run { UIScreen.main.scale }

        do {
            let (data, response) = try await AppURLSession.images.data(for: request)
            guard !Task.isCancelled else { return }

            AppURLSession.imageURLCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data), for: request)

            guard let ui = Self.decode(data: data, scale: scale, maxPixelSize: BindrImageSizing.detailMaxPixelSize) else {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    guard self?.currentLowURL == url else { return }
                    self?.state = .failed
                }
                return
            }
            let key = Self.cacheKey(url: url, scale: scale)
            await DecodedImageMemoryCache.shared.set(ui, for: key)

            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                guard self?.currentLowURL == url else { return }
                self?.state = .loadingHigh(ui)
            }

            if let highURL = highURL, highURL != url {
                await loadHighResAsync(highURL)
            } else {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    guard self?.currentLowURL == url else { return }
                    self?.state = .highReady(ui)
                }
            }
        } catch {
            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                guard self?.currentLowURL == url else { return }
                self?.state = .failed
            }
        }
    }

    private func loadHighResAsync(_ url: URL?) async {
        guard let url else { return }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        let scale = await MainActor.run { UIScreen.main.scale }

        do {
            let (data, response) = try await AppURLSession.images.data(for: request)
            guard !Task.isCancelled else { return }

            AppURLSession.imageURLCache.storeCachedResponse(
                CachedURLResponse(response: response, data: data), for: request)

            if let ui = Self.decode(data: data, scale: scale, maxPixelSize: BindrImageSizing.detailMaxPixelSize) {
                let key = Self.cacheKey(url: url, scale: scale)
                await DecodedImageMemoryCache.shared.set(ui, for: key)
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    guard self?.currentHighURL == url else { return }
                    self?.state = .highReady(ui)
                }
            }
        } catch { }
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
                    .bindrRasterizedForDisplay()
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))

            case .highReady(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .bindrRasterizedForDisplay()
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            case .failed:
                placeholder()
            }
        }
        .onChange(of: loader.readyImage) { _, image in
            if let image { onImageLoaded?(image) }
        }
        .task(id: "\(lowResURL?.absoluteString ?? "")|\(highResURL?.absoluteString ?? "")|\(offlineContext?.isOfflineEnabled == true)|\(offlineContext?.packDataRevision ?? 0)") {
            await loader.load(lowResURL: lowResURL, highResURL: highResURL, localLowResURL: localLowResURL)
        }
    }
}

// MARK: - Optimized Cached Image with Downsampling

@Observable
private final class OptimizedImageLoader {
    var image: UIImage?
    private var currentURL: URL?
    private var targetSize: CGSize?

    func load(url: URL?, localURL: URL? = nil, targetSize: CGSize? = nil) async {
        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        if url == currentURL, image != nil, localURL == nil { return }

        currentURL = url
        self.targetSize = targetSize
        image = nil

        let scale = await MainActor.run { UIScreen.main.scale }

        var decoded: UIImage?

        if let localURL = localURL, let data = try? Data(contentsOf: localURL) {
            decoded = ThumbnailImageDecode.downsampled(data: data, targetSize: targetSize, scale: scale)
        }

        if decoded == nil {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            if let cached = AppURLSession.imageURLCache.cachedResponse(for: request) {
                decoded = ThumbnailImageDecode.downsampled(data: cached.data, targetSize: targetSize, scale: scale)
            } else {
                do {
                    let (data, response) = try await AppURLSession.images.data(for: request)
                    guard !Task.isCancelled else { return }
                    AppURLSession.imageURLCache.storeCachedResponse(
                        CachedURLResponse(response: response, data: data), for: request)
                    decoded = ThumbnailImageDecode.downsampled(data: data, targetSize: targetSize, scale: scale)
                } catch { }
            }
        }

        let finalImage = decoded
        await MainActor.run { [weak self] in
            guard let self, !Task.isCancelled else { return }
            guard self.currentURL == url else { return }
            self.image = finalImage
        }
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
            await loader.load(url: url, localURL: localURL, targetSize: targetSize)
        }
    }
}
