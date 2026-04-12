import SwiftUI

/// Set logos from R2 — prefers downloaded offline file when present; otherwise same candidate fallback as before.
struct SetLogoAsyncImage: View {
    let logoSrc: String
    let height: CGFloat
    let brand: TCGBrand

    @Environment(AppServices.self) private var services

    @State private var candidateIndex = 0
    @State private var lastFailureHandledAtIndex: Int?

    private var trimmed: String {
        logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urls: [URL] {
        guard !trimmed.isEmpty else { return [] }
        return AppConfiguration.setLogoURLCandidates(logoSrc: trimmed)
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                Color.clear
            } else if let local = OfflineImageStore.shared.localFileURL(relativePath: trimmed, brand: brand),
                      let ui = UIImage(contentsOfFile: local.path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else if services.offlineImageSettings.strictOfflineImageMode {
                Color.clear
            } else if candidateIndex < urls.count, !urls.isEmpty {
                AsyncImage(url: urls[candidateIndex]) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        let nextIndex = candidateIndex + 1
                        if nextIndex < urls.count {
                            Color.clear
                                .onAppear {
                                    guard lastFailureHandledAtIndex != candidateIndex else { return }
                                    lastFailureHandledAtIndex = candidateIndex
                                    candidateIndex = nextIndex
                                }
                        } else {
                            Color.clear
                        }
                    case .empty:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .id("\(trimmed)-\(candidateIndex)")
            } else {
                Color.clear
            }
        }
        .id("\(trimmed)-\(services.offlineImageDownload.packDataRevision)-\(services.offlineImageSettings.strictOfflineImageMode)")
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .onChange(of: trimmed) { _, _ in
            candidateIndex = 0
            lastFailureHandledAtIndex = nil
        }
    }
}

/// Set rarity / expansion symbol from `sets.json` `symbolSrc`.
struct SetSymbolAsyncImage: View {
    let symbolSrc: String
    let height: CGFloat
    let brand: TCGBrand

    @Environment(AppServices.self) private var services

    @State private var candidateIndex = 0
    @State private var lastFailureHandledAtIndex: Int?

    private var trimmed: String {
        symbolSrc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urls: [URL] {
        guard !trimmed.isEmpty else { return [] }
        return AppConfiguration.setSymbolURLCandidates(symbolSrc: trimmed)
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                Color.clear
            } else if let local = OfflineImageStore.shared.localFileURL(relativePath: trimmed, brand: brand),
                      let ui = UIImage(contentsOfFile: local.path) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            } else if services.offlineImageSettings.strictOfflineImageMode {
                Color.clear
            } else if candidateIndex < urls.count, !urls.isEmpty {
                AsyncImage(url: urls[candidateIndex]) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        let nextIndex = candidateIndex + 1
                        if nextIndex < urls.count {
                            Color.clear
                                .onAppear {
                                    guard lastFailureHandledAtIndex != candidateIndex else { return }
                                    lastFailureHandledAtIndex = candidateIndex
                                    candidateIndex = nextIndex
                                }
                        } else {
                            Color.clear
                        }
                    case .empty:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
                .id("\(trimmed)-\(candidateIndex)")
            } else {
                Color.clear
            }
        }
        .id("\(trimmed)-\(services.offlineImageDownload.packDataRevision)-\(services.offlineImageSettings.strictOfflineImageMode)")
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .onChange(of: trimmed) { _, _ in
            candidateIndex = 0
            lastFailureHandledAtIndex = nil
        }
    }
}
