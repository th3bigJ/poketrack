import SwiftUI

/// Set logos from R2 with candidate URL fallback.
struct SetLogoAsyncImage: View {
    let logoSrc: String
    let height: CGFloat
    let brand: TCGBrand

    private var trimmed: String {
        logoSrc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urls: [URL] {
        guard !trimmed.isEmpty else { return [] }
        return AppConfiguration.setLogoURLCandidates(logoSrc: trimmed)
    }

    private var primaryURL: URL? {
        urls.first
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                Color.clear
            } else {
                CachedAsyncImage(url: primaryURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    }
}

/// Set rarity / expansion symbol from `sets.json` `symbolSrc`.
struct SetSymbolAsyncImage: View {
    let symbolSrc: String
    let height: CGFloat
    let brand: TCGBrand

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
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .onChange(of: trimmed) { _, _ in
            candidateIndex = 0
            lastFailureHandledAtIndex = nil
        }
    }
}
