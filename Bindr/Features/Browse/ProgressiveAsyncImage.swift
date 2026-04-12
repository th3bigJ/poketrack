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

    private var loadTask: Task<Void, Never>?
    private var currentLowURL: URL?
    private var currentHighURL: URL?
    private var lastAppliedStrict: Bool?

    func load(
        lowResURL: URL?,
        highResURL: URL?,
        offlineLowRelativePath: String?,
        offlineHighRelativePath: String?,
        offlineBrand: TCGBrand?,
        strictOfflineNoCDN: Bool
    ) {
        loadTask?.cancel()

        let previousStrict = lastAppliedStrict
        if lowResURL == currentLowURL && highResURL == currentHighURL && previousStrict == strictOfflineNoCDN {
            switch state {
            case .lowReady, .loadingHigh, .highReady:
                return
            default:
                break
            }
        }
        lastAppliedStrict = strictOfflineNoCDN

        currentLowURL = lowResURL
        currentHighURL = highResURL

        let capturedLow = lowResURL
        let capturedHigh = highResURL
        let capturedRelLow = offlineLowRelativePath
        let capturedRelHigh = offlineHighRelativePath
        let capturedBrand = offlineBrand
        let capturedStrict = strictOfflineNoCDN

        // Disk + URLCache + decode must not run on the main actor (grid/detail jank in offline mode).
        loadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.runProgressiveLoad(
                lowResURL: capturedLow,
                highResURL: capturedHigh,
                offlineLowRelativePath: capturedRelLow,
                offlineHighRelativePath: capturedRelHigh,
                offlineBrand: capturedBrand,
                strictOfflineNoCDN: capturedStrict
            )
        }
    }

    /// Decode pack bytes like grid thumbnails (ImageIO) so formats match `CachedAsyncImage`; fall back to `UIImage(data:)`.
    private func decodeProgressiveDisk(data: Data) async -> UIImage? {
        let (scale, width) = await MainActor.run {
            (UIScreen.main.scale, UIScreen.main.bounds.width)
        }
        let targetW = min(width - 32, 520) * scale
        let targetH = targetW * 7 / 5
        let target = CGSize(width: targetW, height: targetH)
        return ThumbnailImageDecode.downsampled(data: data, targetSize: target, scale: scale)
            ?? UIImage(data: data)
    }

    private func runProgressiveLoad(
        lowResURL: URL?,
        highResURL: URL?,
        offlineLowRelativePath: String?,
        offlineHighRelativePath: String?,
        offlineBrand: TCGBrand?,
        strictOfflineNoCDN: Bool
    ) async {
        // 1) Offline pack: local low-res file, then optional high-res path (same keys as manifest).
        if let brand = offlineBrand {
            if let rel = offlineLowRelativePath, !rel.isEmpty,
               let local = OfflineImageStore.shared.localFileURL(relativePath: rel, brand: brand),
               let diskData = try? Data(contentsOf: local),
               let ui = await decodeProgressiveDisk(data: diskData) {
                if strictOfflineNoCDN {
                    await MainActor.run { [weak self] in
                        guard !Task.isCancelled else { return }
                        self?.state = .highReady(ui)
                    }
                    return
                }
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

            if let relHigh = offlineHighRelativePath, !relHigh.isEmpty,
               relHigh != offlineLowRelativePath,
               let local = OfflineImageStore.shared.localFileURL(relativePath: relHigh, brand: brand),
               let diskData = try? Data(contentsOf: local),
               let ui = await decodeProgressiveDisk(data: diskData) {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .highReady(ui)
                }
                return
            }
        }

        // 2) Strict offline: URLCache for low URL, then high (no new network; detail may have cached high only).
        if strictOfflineNoCDN {
            if let lowURL = lowResURL {
                let lowRequest = URLRequest(url: lowURL, cachePolicy: .returnCacheDataElseLoad)
                if let cached = AppURLSession.imageURLCache.cachedResponse(for: lowRequest),
                   let ui = await decodeProgressiveDisk(data: cached.data) {
                    await MainActor.run { [weak self] in
                        guard !Task.isCancelled else { return }
                        self?.state = .highReady(ui)
                    }
                    return
                }
            }
            if let highURL = highResURL {
                let highRequest = URLRequest(url: highURL, cachePolicy: .returnCacheDataElseLoad)
                if let cached = AppURLSession.imageURLCache.cachedResponse(for: highRequest),
                   let ui = await decodeProgressiveDisk(data: cached.data) {
                    await MainActor.run { [weak self] in
                        guard !Task.isCancelled else { return }
                        self?.state = .highReady(ui)
                    }
                    return
                }
            }
            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.state = .failed
            }
            return
        }

        if let highURL = highResURL {
            let highRequest = URLRequest(url: highURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = AppURLSession.imageURLCache.cachedResponse(for: highRequest),
               let ui = UIImage(data: cached.data) {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .highReady(ui)
                }
                return
            }
        }

        if let lowURL = lowResURL {
            let lowRequest = URLRequest(url: lowURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = AppURLSession.imageURLCache.cachedResponse(for: lowRequest),
               let ui = UIImage(data: cached.data) {
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
struct ProgressiveAsyncImage<Placeholder: View>: View {
    let lowResURL: URL?
    let highResURL: URL?
    let offlineLowRelativePath: String?
    let offlineHighRelativePath: String?
    let offlineBrand: TCGBrand?
    let placeholder: () -> Placeholder

    @Environment(AppServices.self) private var services
    @State private var loader = ProgressiveImageLoader()

    init(
        lowResURL: URL?,
        highResURL: URL? = nil,
        offlineLowRelativePath: String? = nil,
        offlineHighRelativePath: String? = nil,
        offlineBrand: TCGBrand? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.lowResURL = lowResURL
        self.highResURL = highResURL
        self.offlineLowRelativePath = offlineLowRelativePath
        self.offlineHighRelativePath = offlineHighRelativePath
        self.offlineBrand = offlineBrand
        self.placeholder = placeholder
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
        // `strictOfflineImageMode` is part of `task(id:)` so turning Offline mode off re-runs load and can fetch high-res (toggle is rare vs scrolling).
        .task(id: "\(lowResURL?.absoluteString ?? "")|\(highResURL?.absoluteString ?? "")|\(offlineLowRelativePath ?? "")|\(offlineHighRelativePath ?? "")|\(offlineBrand?.rawValue ?? "")|\(services.offlineImageDownload.packDataRevision)|\(services.offlineImageSettings.strictOfflineImageMode)") {
            loader.load(
                lowResURL: lowResURL,
                highResURL: highResURL,
                offlineLowRelativePath: offlineLowRelativePath,
                offlineHighRelativePath: offlineHighRelativePath,
                offlineBrand: offlineBrand,
                strictOfflineNoCDN: services.offlineImageSettings.strictOfflineImageMode
            )
        }
        .onChange(of: services.offlineImageSettings.strictOfflineImageMode) { _, _ in
            loader.load(
                lowResURL: lowResURL,
                highResURL: highResURL,
                offlineLowRelativePath: offlineLowRelativePath,
                offlineHighRelativePath: offlineHighRelativePath,
                offlineBrand: offlineBrand,
                strictOfflineNoCDN: services.offlineImageSettings.strictOfflineImageMode
            )
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
    
    func load(url: URL?, targetSize: CGSize? = nil) {
        loadTask?.cancel()

        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        if url == currentURL, image != nil { return }

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

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                guard self.currentURL == capturedURL else { return }
                self.image = decoded
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
