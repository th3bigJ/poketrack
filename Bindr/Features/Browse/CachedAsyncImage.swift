import SwiftUI
import UIKit

@Observable
private final class ImageLoader {
    var image: UIImage?
    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?
    private var targetSize: CGSize?
    /// Last strict policy we applied for `currentURL` (avoids redundant reloads; must reload when strict flips).
    private var lastAppliedStrict: Bool?

    func load(
        url: URL?,
        targetSize: CGSize?,
        offlineRelativePath: String?,
        offlineBrand: TCGBrand?,
        strictOfflineNoCDN: Bool
    ) {
        loadTask?.cancel()

        guard let url else {
            currentURL = nil
            image = nil
            lastAppliedStrict = nil
            return
        }

        let previousStrict = lastAppliedStrict
        if url == currentURL, image != nil, previousStrict == strictOfflineNoCDN {
            return
        }
        lastAppliedStrict = strictOfflineNoCDN

        currentURL = url
        self.targetSize = targetSize
        image = nil

        let capturedURL = url
        let capturedTarget = targetSize
        let capturedRel = offlineRelativePath
        let capturedBrand = offlineBrand
        let capturedStrict = strictOfflineNoCDN

        // All disk / URLCache / network / decode happens off the main thread so scrolling stays fluid
        // (especially offline mode where every cell hits disk or cache synchronously).
        loadTask = Task.detached(priority: .utility) { [weak self] in
            let scale = await MainActor.run { UIScreen.main.scale }
            let request = URLRequest(url: capturedURL, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

            var decoded: UIImage?

            if let brand = capturedBrand,
               let rel = capturedRel,
               !rel.isEmpty,
               let local = OfflineImageStore.shared.localFileURL(relativePath: rel, brand: brand),
               let diskData = try? Data(contentsOf: local) {
                decoded = ThumbnailImageDecode.downsampled(data: diskData, targetSize: capturedTarget, scale: scale)
            } else if capturedStrict {
                if let cached = AppURLSession.imageURLCache.cachedResponse(for: request) {
                    decoded = ThumbnailImageDecode.downsampled(data: cached.data, targetSize: capturedTarget, scale: scale)
                }
            } else if let cached = AppURLSession.imageURLCache.cachedResponse(for: request) {
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

/// Drop-in for `AsyncImage` backed by `URLCache` with optional downsampling.
/// Reliable in `LazyVGrid` and memory-efficient for thumbnails.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let targetSize: CGSize?
    private let offlineRelativePath: String?
    private let offlineBrand: TCGBrand?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @Environment(AppServices.self) private var services
    @State private var loader = ImageLoader()

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        offlineRelativePath: String? = nil,
        offlineBrand: TCGBrand? = nil,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.targetSize = targetSize
        self.offlineRelativePath = offlineRelativePath
        self.offlineBrand = offlineBrand
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
        // Include `strictOfflineImageMode` in `task(id:)` so toggling Offline mode refreshes cells (toggle is infrequent).
        .task(id: "\(url?.absoluteString ?? "")|\(offlineRelativePath ?? "")|\(offlineBrand?.rawValue ?? "")|\(services.offlineImageDownload.packDataRevision)|\(services.offlineImageSettings.strictOfflineImageMode)") {
            loader.load(
                url: url,
                targetSize: targetSize,
                offlineRelativePath: offlineRelativePath,
                offlineBrand: offlineBrand,
                strictOfflineNoCDN: services.offlineImageSettings.strictOfflineImageMode
            )
        }
        .onChange(of: services.offlineImageSettings.strictOfflineImageMode) { _, _ in
            loader.load(
                url: url,
                targetSize: targetSize,
                offlineRelativePath: offlineRelativePath,
                offlineBrand: offlineBrand,
                strictOfflineNoCDN: services.offlineImageSettings.strictOfflineImageMode
            )
        }
    }
}
