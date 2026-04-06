import SwiftUI

@Observable
private final class ImageLoader {
    var image: UIImage?
    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?

    func load(url: URL?) {
        loadTask?.cancel()

        guard let url else {
            currentURL = nil
            image = nil
            return
        }

        // Skip only when this URL already produced a decoded image; if `image` is nil, reload (e.g. after `.task` cancellation).
        if url == currentURL, image != nil { return }

        currentURL = url
        image = nil

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)

        if let cached = URLCache.shared.cachedResponse(for: request),
           let ui = UIImage(data: cached.data) {
            image = ui
            return
        }

        loadTask = Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                if let ui = UIImage(data: data) {
                    URLCache.shared.storeCachedResponse(
                        CachedURLResponse(response: response, data: data), for: request)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.image = ui
                    }
                }
            } catch { }
        }
    }

    func cancel() {
        loadTask?.cancel()
    }
}

/// Drop-in for `AsyncImage` backed by `URLCache` — reliable in `LazyVGrid`.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var loader = ImageLoader()

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let ui = loader.image {
                content(Image(uiImage: ui))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            loader.load(url: url)
        }
    }
}
