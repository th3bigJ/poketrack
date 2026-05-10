import SwiftUI
import UIKit

/// A premium representation of a binder cover, featuring procedural textures,
/// a reinforced spine, an ornamental tinted header, and an optional fan of
/// "peeking" card-back thumbnails. Designed in an A4 portrait ratio so it
/// reads as a real binder spine rather than a tile.
struct BinderCoverView: View {
    @Environment(AppServices.self) private var services
    let binder: Binder
    
    /// Optional override for the peeking thumbnails, used to pass 
    /// already-loaded URLs from a grid cell to the fullscreen morph.
    var peekingURLsOverride: [URL?]? = nil
    /// Optional subtitle override for situations where we want to match a 
    /// specific string (e.g. from the grid cell) rather than the default 
    /// "X cards · Y x Y" format.
    var subtitleOverride: String? = nil

    /// If true, the view uses smaller refinements suitable for list cells.
    var compact: Bool = false

    /// Optional formatted total value (e.g. "£1,779") rendered prominently at
    /// the bottom of the cover. Pass `nil` to omit (e.g. for empty binders or
    /// preview/creation flows where the value isn't meaningful yet).
    var valueText: String? = nil

    @State private var resolvedPeekingURLs: [URL?] = []
    @State private var embossedURL: URL? = nil
    
    /// Cover text color selection for title/subtitle/value.
    var titleTextColor: BinderTitleTextColor = .gold
    /// Cover text font selection for title/subtitle/value.
    var titleFontStyle: BinderTitleFontStyle = .serif

    // MARK: - Tinted-white accent palette
    //
    // The default cover text used to be a warm gold which clashed with the
    // app's overall theme. Instead we now render the title, ornament, and
    // value as predominantly **white** with a small amount of the binder's own
    // base colour mixed in — so the text reads bright on every binder body
    // (navy/crimson/etc.) but still picks up the binder's hue and feels
    // cohesive with the rest of the app chrome.
    private func tintedWhite(intensity: Double) -> Color {
        let ui = UIColor(BinderColourPalette.color(named: binder.colour))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamped = max(0, min(1, intensity))
        let mr = (1 - clamped) + clamped * Double(r)
        let mg = (1 - clamped) + clamped * Double(g)
        let mb = (1 - clamped) + clamped * Double(b)
        return Color(red: mr, green: mg, blue: mb)
    }
    /// Top stop of the title gradient — almost pure white with a faint tint.
    private var defaultTitleHighlight: Color { tintedWhite(intensity: 0.10) }
    /// Bottom stop of the title gradient — slightly more of the binder hue
    /// so the gradient reads as a subtle wash of colour.
    private var defaultTitleAccent: Color { tintedWhite(intensity: 0.30) }
    private var ornamentColor: Color {
        binder.titleTextColorKind == .gold ? defaultTitleAccent : binder.titleTextColorKind.swiftUIColor
    }
    private var titleTextStyle: AnyShapeStyle {
        if binder.titleTextColorKind == .gold {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [defaultTitleHighlight, defaultTitleAccent],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(binder.titleTextColorKind.swiftUIColor)
    }

    var body: some View {
        GeometryReader { geo in
            // Reference height is 600pt (premium view). 
            // We scale everything proportionally based on the current height.
            let scale = geo.size.height / 600.0
            
            ZStack(alignment: .leading) {
                // Main binder body (tactile material)
                BinderTextureView(
                    colourName: binder.colour,
                    texture: binder.textureKind,
                    seed: binder.textureSeed,
                    compact: compact
                )
                .clipShape(RoundedRectangle(cornerRadius: geo.size.height * 0.03, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: geo.size.height * 0.015, x: 0, y: geo.size.height * 0.008)

                // Embossed cover art (sits "in" the material)
                if !binder.showCardPreview, let url = embossedURL {
                    embossedArtLayer(url: url, scale: scale)
                        .padding(.leading, 36 * scale) // Stay right of the spine
                }

                // Foreground content — ornament at top, title in upper portion,
                // optional card fan in the middle, value at the bottom.
                VStack(spacing: 0) {
                    Spacer().frame(height: 22 * scale)

                    topOrnament(scale: scale)

                    Spacer().frame(height: 14 * scale)

                    titleBlock(scale: scale)

                    if binder.showCardPreview {
                        Spacer(minLength: 8 * scale)

                        let displayURLs = peekingURLsOverride ?? resolvedPeekingURLs
                        if !displayURLs.isEmpty {
                            HStack(spacing: -70 * scale) {
                                ForEach(0..<displayURLs.count, id: \.self) { index in
                                    peekingCard(url: displayURLs[index], scale: scale, index: index, totalCount: displayURLs.count)
                                }
                            }
                            .frame(height: 145 * scale)
                        }

                        Spacer(minLength: 12 * scale)
                    } else {
                        Spacer(minLength: 0)
                    }

                    if let valueText {
                        valueLabel(valueText, scale: scale)
                            .padding(.bottom, 24 * scale)
                    } else {
                        Spacer().frame(height: 20 * scale)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 36 * scale)
                .padding(.trailing, 14 * scale)

                // Spine overlay (stays on left)
                spineOverlay(scale: scale)
            }
            .task {
                await refreshAssets()
            }
            // Re-load if the binder's state changes
            .onChange(of: binder.showCardPreview) { Task { await refreshAssets() } }
            .onChange(of: binder.embossedCardID) { Task { await refreshAssets() } }
            .onChange(of: binder.embossMode) { Task { await refreshAssets() } }
        }
    }

    private func refreshAssets() async {
        // 1. Resolve peeking cards (if needed)
        if binder.showCardPreview && peekingURLsOverride == nil {
            let slots = binder.slotList.prefix(3)
            var urls: [URL?] = []
            for slot in slots {
                if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                    urls.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
                }
            }
            while urls.count < 3 { urls.append(nil) }
            resolvedPeekingURLs = urls
        }

        // 2. Resolve embossed art — prefer high-res for detail
        if !binder.showCardPreview, let cardID = binder.embossedCardID {
            if let card = await services.cardData.loadCard(masterCardId: cardID) {
                let path = card.imageHighSrc?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? card.imageHighSrc!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : card.imageLowSrc
                embossedURL = AppConfiguration.imageURL(relativePath: path)
            }
        } else {
            embossedURL = nil
        }
    }

    // MARK: - Top ornament (tinted line + diamond)

    private func topOrnament(scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            ornamentLine(scale: scale)
            ornamentDiamond(scale: scale)
            ornamentLine(scale: scale)
        }
        .frame(maxWidth: 160 * scale)
    }

    private func ornamentLine(scale: CGFloat) -> some View {
        LinearGradient(
            colors: [
                ornamentColor.opacity(0.0),
                ornamentColor.opacity(0.85),
                ornamentColor.opacity(0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1.4 * scale)
    }

    private func ornamentDiamond(scale: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(
                colors: titleTextColor == .gold
                    ? [defaultTitleHighlight, defaultTitleAccent]
                    : [ornamentColor.opacity(0.95), ornamentColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .rotationEffect(.degrees(45))
            .frame(width: 7 * scale, height: 7 * scale)
            .shadow(color: .black.opacity(0.4), radius: 0.5 * scale, x: 0, y: 0.5 * scale)
    }

    // MARK: - Title block (title + subtitle in tinted white)

    private func titleBlock(scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            Text(binder.title.isEmpty ? "Binder name…" : binder.title)
                .font(.system(size: 32 * scale, weight: .bold, design: binder.titleFontStyleKind.fontDesign))
                .foregroundStyle(titleTextStyle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .opacity(binder.title.isEmpty ? 0.5 : 1)
                .shadow(color: .black.opacity(0.4), radius: 1.5 * scale, x: 0, y: 1 * scale)

            let generatedSubtitle = "\(binder.slotList.count) \(binder.slotList.count == 1 ? "card" : "cards")"
            if let override = subtitleOverride {
                Text(override.uppercased())
                    .font(.system(size: 14 * scale, weight: .semibold, design: binder.titleFontStyleKind.fontDesign))
                    .tracking(2.0 * scale)
                    .foregroundStyle(binder.titleTextColorKind == .gold ? defaultTitleHighlight.opacity(0.85) : binder.titleTextColorKind.swiftUIColor.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(generatedSubtitle.uppercased())
                    .font(.system(size: 14 * scale, weight: .semibold, design: binder.titleFontStyleKind.fontDesign))
                    .tracking(2.0 * scale)
                    .foregroundStyle(binder.titleTextColorKind == .gold ? defaultTitleHighlight.opacity(0.85) : binder.titleTextColorKind.swiftUIColor.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8 * scale)
    }

    // MARK: - Value label (tinted serif at the bottom)

    private func valueLabel(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 44 * scale, weight: .bold, design: binder.titleFontStyleKind.fontDesign))
            .foregroundStyle(titleTextStyle)
            .shadow(color: .black.opacity(0.45), radius: 1.5 * scale, x: 0, y: 1 * scale)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8 * scale)
    }

    // MARK: - Spine overlay (left edge with binding rings)

    private func spineOverlay(scale: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // Darkened spine strip
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(width: 32 * scale)

            // Binding rings/dots
            VStack(spacing: 44 * scale) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(LinearGradient(
                            colors: [.black.opacity(0.4), .black.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 7 * scale, height: 7 * scale)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5 * scale)
                        }
                }
            }
            .frame(width: 32 * scale)
            .padding(.vertical, 36 * scale)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Embossed art layer

    private func embossedArtLayer(url: URL, scale: CGFloat) -> some View {
        let isCharacter = binder.embossModeKind == .character
        let cardW: CGFloat = 290 * scale
        // Full card: show the entire card shape. Character: zoom to top 55% (artwork box)
        let cardH: CGFloat = isCharacter ? (cardW / 0.714) * 0.55 : cardW / 0.714

        return CachedAsyncImage(url: url, targetSize: CGSize(width: Int(cardW * 2), height: Int(cardH * 2))) { img in
            ZStack {
                // ── Layer 1: Dark offset copy  (top-left = "pressed shadow") ──
                img.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardW, height: cardH, alignment: isCharacter ? .top : .center)
                    .clipped()
                    .grayscale(1)
                    .brightness(-0.5)      // very dark
                    .opacity(0.55)
                    .offset(x: -1.5 * scale, y: -1.5 * scale)
                    .blendMode(.multiply)

                // ── Layer 2: Light offset copy (bottom-right = "raised highlight") ──
                img.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardW, height: cardH, alignment: isCharacter ? .top : .center)
                    .clipped()
                    .grayscale(1)
                    .brightness(0.6)       // very light
                    .opacity(0.55)
                    .offset(x: 1.5 * scale, y: 1.5 * scale)
                    .blendMode(.screen)

                // ── Layer 3: Base card at full colour, low opacity ──
                // This lets you see the art "tinted" into the binder material
                img.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardW, height: cardH, alignment: isCharacter ? .top : .center)
                    .clipped()
                    .grayscale(0.7)
                    .opacity(0.22)
                    .blendMode(.overlay)
            }
            .clipShape(RoundedRectangle(cornerRadius: isCharacter ? 12 * scale : 8 * scale, style: .continuous))
        } placeholder: {
            ProgressView().controlSize(.small).opacity(0.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 105 * scale)
        .padding(.bottom, 30 * scale)
    }

    // MARK: - Peeking card thumbnail

    @ViewBuilder
    private func peekingCard(url: URL?, scale: CGFloat, index: Int, totalCount: Int) -> some View {
        let middleIndex = Double(totalCount - 1) / 2.0
        let relativeIndex = Double(index) - middleIndex

        // Fanning geometry: cards rotate from the bottom centre to create
        // a natural "spread".
        let rotation = relativeIndex * 15.0
        let xOffset = relativeIndex * 8 * scale
        let yOffset = abs(relativeIndex) * 12 * scale

        ZStack {
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .fill(Color(white: 0.15)) // Dark base for empty/loading
                .overlay {
                    if let url {
                        CachedAsyncImage(url: url, targetSize: CGSize(width: 140 * scale, height: 196 * scale)) { img in
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        // Glassy placeholder for empty slots
                        RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .blur(radius: 1 * scale)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3 * scale, x: -2 * scale, y: 2 * scale)

            // Subtle edge highlight
            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5 * scale)
        }
        .aspectRatio(5/7, contentMode: .fit)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: xOffset, y: yOffset)
        .zIndex(-Double(index))
    }
}


// MARK: - Convenience Helpers

extension BinderCoverView {
    /// Create a cover view from a model instance.
    init(binder: Binder, compact: Bool = false, valueText: String? = nil) {
        self.binder = binder
        self.compact = compact
        self.valueText = valueText
    }

    /// Convenience modifier to override the subtitle.
    func subtitleOverride(_ text: String?) -> Self {
        var copy = self
        copy.subtitleOverride = text
        return copy
    }

    /// Convenience modifier to override the peeking URLs.
    func peekingURLsOverride(_ urls: [URL?]?) -> Self {
        var copy = self
        copy.peekingURLsOverride = urls
        return copy
    }
}


