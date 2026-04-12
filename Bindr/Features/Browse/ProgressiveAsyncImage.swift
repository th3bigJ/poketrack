import SwiftUI

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
    
    private var lowLoadTask: Task<Void, Never>?
    private var highLoadTask: Task<Void, Never>?
    private var currentLowURL: URL?
    private var currentHighURL: URL?
    
    /// Load with progressive enhancement: low-res first, then high-res
    func load(lowResURL: URL?, highResURL: URL?) {
        // Cancel existing tasks
        lowLoadTask?.cancel()
        highLoadTask?.cancel()
        
        // If URLs haven't changed and we have an image, keep it
        if lowResURL == currentLowURL && highResURL == currentHighURL {
            switch state {
            case .lowReady, .loadingHigh, .highReady:
                return  // Already have something to show
            default:
                break
            }
        }
        
        currentLowURL = lowResURL
        currentHighURL = highResURL
        
        // Check cache first for instant display
        if let highURL = highResURL {
            let highRequest = URLRequest(url: highURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = URLCache.shared.cachedResponse(for: highRequest),
               let ui = UIImage(data: cached.data) {
                state = .highReady(ui)
                return
            }
        }
        
        if let lowURL = lowResURL {
            let lowRequest = URLRequest(url: lowURL, cachePolicy: .returnCacheDataElseLoad)
            if let cached = URLCache.shared.cachedResponse(for: lowRequest),
               let ui = UIImage(data: cached.data) {
                // Have low-res cached, start loading high-res
                state = .loadingHigh(ui)
                loadHighRes(highResURL)
                return
            }
        }
        
        // Start with low-res load
        state = .loadingLow
        loadLowRes(lowResURL, thenLoadHigh: highResURL)
    }
    
    private func loadLowRes(_ url: URL?, thenLoadHigh highURL: URL?) {
        guard let url else {
            // No low-res, try high-res directly
            loadHighRes(highURL)
            return
        }
        
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        
        lowLoadTask = Task { [weak self] in
            do {
                let (data, response) = try await AppURLSession.images.data(for: request)
                guard !Task.isCancelled else { return }
                
                // Store in cache
                URLCache.shared.storeCachedResponse(
                    CachedURLResponse(response: response, data: data), for: request)
                
                if let ui = UIImage(data: data) {
                    await MainActor.run { [weak self] in
                        guard !Task.isCancelled else { return }
                        self?.state = .loadingHigh(ui)
                    }
                    
                    // Immediately start high-res load
                    if let highURL = highURL, highURL != url {
                        self?.loadHighRes(highURL)
                    } else {
                        // No high-res or same URL, we're done
                        await MainActor.run { [weak self] in
                            self?.state = .highReady(ui)
                        }
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.state = .failed
                }
            }
        }
    }
    
    private func loadHighRes(_ url: URL?) {
        guard let url else { return }
        
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
        
        highLoadTask = Task { [weak self] in
            do {
                let (data, response) = try await AppURLSession.images.data(for: request)
                guard !Task.isCancelled else { return }
                
                URLCache.shared.storeCachedResponse(
                    CachedURLResponse(response: response, data: data), for: request)
                
                if let ui = UIImage(data: data) {
                    await MainActor.run { [weak self] in
                        guard !Task.isCancelled else { return }
                        self?.state = .highReady(ui)
                    }
                }
            } catch {
                // High-res failed, but we might have low-res still showing
            }
        }
    }
    
    func cancel() {
        lowLoadTask?.cancel()
        highLoadTask?.cancel()
    }
}

/// Progressive image view that shows low-res immediately, then smoothly crossfades to high-res.
/// Use this for detail views where image quality matters and perceived performance is critical.
struct ProgressiveAsyncImage<Placeholder: View>: View {
    let lowResURL: URL?
    let highResURL: URL?
    let placeholder: () -> Placeholder
    
    @State private var loader = ProgressiveImageLoader()
    
    init(
        lowResURL: URL?,
        highResURL: URL? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.lowResURL = lowResURL
        self.highResURL = highResURL
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
        .task(id: lowResURL?.absoluteString ?? "" + (highResURL?.absoluteString ?? "")) {
            loader.load(lowResURL: lowResURL, highResURL: highResURL)
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
        
        // Skip only when this URL already produced a decoded image
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
