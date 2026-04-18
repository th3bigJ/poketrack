import SwiftUI

/// A premium representation of a binder cover, featuring procedural textures,
/// a reinforced spine, and "peeking" card-back thumbnails on the right edge.
struct BinderCoverView: View {
    let title: String
    let subtitle: String?
    let colourName: String
    let texture: BinderTexture
    let seed: Int
    let peekingCardURLs: [URL?]
    
    /// If true, the view uses smaller refinements suitable for list cells.
    var compact: Bool = false
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Main Binder Body
            mainBody
                .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: compact ? 4 : 8, x: 0, y: 4)
            
            // Spine Overlay
            spineOverlay
            
            // Text Content
            textContent
                .padding(.leading, compact ? 28 : 40)
                .padding(.trailing, 60) // Space for peeking cards
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 120 : 180)
    }
    
    private var mainBody: some View {
        ZStack(alignment: .trailing) {
            // The procedural material layer
            BinderTextureView(
                colourName: colourName,
                texture: texture,
                seed: seed,
                compact: compact
            )
            
            // Peeking Cards - fanned from the right side
            HStack(spacing: compact ? -38 : -55) {
                ForEach(0..<peekingCardURLs.count, id: \.self) { index in
                    peekingCard(url: peekingCardURLs[index], index: index)
                }
            }
            .padding(.trailing, compact ? 12 : 20)
            .offset(x: compact ? 12 : 18)
        }
    }
    
    private var spineOverlay: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Darkened spine strip
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: compact ? 20 : 32)
                
                // Binding Rings/Dots
                VStack(spacing: compact ? 24 : 36) {
                    ForEach(0..<3) { _ in
                        Circle()
                            .fill(LinearGradient(
                                colors: [.black.opacity(0.4), .black.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            }
                    }
                }
                .frame(width: compact ? 20 : 32)
                .padding(.vertical, compact ? 20 : 30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
        .allowsHitTesting(false)
    }
    
    private var textContent: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            Spacer()
            Text(title.isEmpty ? "Binder name..." : title)
                .font(compact ? .headline : .title3.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .opacity(title.isEmpty ? 0.5 : 1)
            
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: compact ? 11 : 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.bottom, compact ? 16 : 24)
    }
    
    @ViewBuilder
    private func peekingCard(url: URL?, index: Int) -> some View {
        let cardCount = peekingCardURLs.count
        let middleIndex = Double(cardCount - 1) / 2.0
        let relativeIndex = Double(index) - middleIndex
        
        // Fanning geometry:
        // Cards rotate from the bottom center to create a natural "spread"
        let rotation = relativeIndex * 12.0
        let xOffset = relativeIndex * (compact ? 2 : 4)
        let yOffset = abs(relativeIndex) * (compact ? 3 : 5)
        
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous)
                .fill(Color(white: 0.15)) // Dark base for empty/loading
                .overlay {
                    if let url {
                        CachedAsyncImage(url: url, targetSize: CGSize(width: 140, height: 196)) { img in
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        // Glassy placeholder for empty slots
                        RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .blur(radius: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3, x: -2, y: 2)
            
            // Subtle edge highlight
            RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        }
        .frame(width: compact ? 45 : 70, height: compact ? 63 : 98)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: xOffset, y: yOffset)
        .zIndex(-Double(index))
    }
}


// MARK: - Convenience Helpers

extension BinderCoverView {
    /// Create a cover view from a model instance.
    init(binder: Binder, compact: Bool = false) {
        // Resolve first 3 card image URLs
        let slots = binder.slotList.prefix(3)
        let urls: [URL?] = slots.map { slot in
            AppConfiguration.imageURL(relativePath: "\(slot.cardID)_low.png") // Placeholder logic, will refine in parent
        }
        
        // Ensure we always have 3 slots (filled with nil if needed)
        var finalURLs = Array(urls)
        while finalURLs.count < 3 { finalURLs.append(nil) }

        self.init(
            title: binder.title,
            subtitle: "\(binder.slotList.count) cards · \(binder.layout.displayName)",
            colourName: binder.colour,
            texture: binder.textureKind,
            seed: binder.textureSeed,
            peekingCardURLs: finalURLs,
            compact: compact
        )
    }
}


#Preview {
    VStack(spacing: 20) {
        BinderCoverView(
            title: "Charizard Vault",
            subtitle: "9 cards · 3 × 3",
            colourName: "crimson",
            texture: .leather,
            seed: 1,
            peekingCardURLs: [nil, nil, nil]
        )
        .padding()
        
        BinderCoverView(
            title: "Blue Chip",
            subtitle: "18 cards · 3 × 3",
            colourName: "navy",
            texture: .suede,
            seed: 2,
            peekingCardURLs: [URL(string: "https://example.com/1.png"), nil, nil],
            compact: true
        )
        .padding()
    }
    .background(Color.black)
}
