
import SwiftUI
import UIKit

enum BinderRingGuide {
    static let normalizedYPositions: [CGFloat] = [0.30, 0.50, 0.70]
}

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
    /// Pre-decoded peeking card faces for synchronous export snapshots.
    var peekingImagesOverride: [UIImage?]? = nil
    /// Pre-decoded embossed art for synchronous export snapshots.
    var embossedImageOverride: UIImage? = nil
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
        if let custom = binder.customTitleTextColor { return custom }
        return binder.titleTextColorKind == .gold ? defaultTitleAccent : binder.titleTextColorKind.swiftUIColor
    }
    private var titleTextStyle: AnyShapeStyle {
        if let custom = binder.customTitleTextColor {
            return AnyShapeStyle(custom)
        }
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

                // Full bleed art layer (when showCardPreview is false)
                if !binder.showCardPreview {
                    Group {
                        if let embossedImageOverride {
                            fullBleedArtLayer(image: Image(uiImage: embossedImageOverride), geo: geo, scale: scale)
                        } else if let url = embossedURL {
                            fullBleedArtLayer(url: url, geo: geo, scale: scale)
                        }
                    }
                }

                // Foreground content — ornament at top, title in upper portion,
                // optional card fan in the middle, value at the bottom.
                // Leading padding matches the card-grid page's leading inset (32pt =
                // spine strip width) so the title / ornament / card fan are
                // visually centred at the same horizontal position as the card grid
                // when the binder is open. Both cover and opened page now share the
                // same (32 leading, 14 trailing) inset, giving a consistent centre.
                VStack(spacing: 0) {
                    Spacer().frame(height: 22 * scale)

                    topOrnament(scale: scale)

                    Spacer().frame(height: 14 * scale)

                    titleBlock(scale: scale)

                    if binder.showCardPreview {
                        Spacer(minLength: 8 * scale)

                        let displayImages = peekingImagesOverride?.compactMap { $0 }
                        let displayURLs = (peekingURLsOverride ?? resolvedPeekingURLs).compactMap { $0 }
                        if let displayImages, !displayImages.isEmpty {
                            HStack(spacing: -70 * scale) {
                                ForEach(0..<displayImages.count, id: \.self) { index in
                                    peekingCardImage(
                                        image: displayImages[index],
                                        scale: scale,
                                        index: index,
                                        totalCount: displayImages.count
                                    )
                                }
                            }
                            .frame(height: 145 * scale)
                        } else if !displayURLs.isEmpty {
                            HStack(spacing: -70 * scale) {
                                ForEach(0..<displayURLs.count, id: \.self) { index in
                                    peekingCard(url: displayURLs[index], scale: scale, index: index, totalCount: displayURLs.count)
                                }
                            }
                            .frame(height: 145 * scale)
                        } else {
                            placeholderPeekingFan(scale: scale)
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
                .padding(.leading, 32 * scale)
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
            .onChange(of: binder.embossedPokemonImageUrl) { Task { await refreshAssets() } }
        }
    }

    private func placeholderPeekingFan(scale: CGFloat) -> some View {
        HStack(spacing: -70 * scale) {
            ForEach(0..<3, id: \.self) { index in
                placeholderPeekingCard(scale: scale, index: index, totalCount: 3)
            }
        }
        .frame(height: 145 * scale)
        .opacity(0.82)
    }

    private func refreshAssets() async {
        // 1. Resolve peeking cards (if needed)
        if binder.showCardPreview && peekingURLsOverride == nil {
            let slots = binder.slotList.prefix(3)
            var urls: [URL?] = []
            for slot in slots {
                if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                    urls.append(AppConfiguration.imageURL(relativePath: card.displayImageSrc))
                }
            }
            resolvedPeekingURLs = urls
        }

        // 2. Resolve embossed art
        guard !binder.showCardPreview else { embossedURL = nil; return }

        if binder.embossModeKind == .character {
            // Character mode: use the Pokémon PNG if set, else fall back to card
            if let imageUrl = binder.embossedPokemonImageUrl {
                embossedURL = AppConfiguration.pokemonArtURL(imageFileName: imageUrl)
            } else if let cardID = binder.embossedCardID,
                      let card = await services.cardData.loadCard(masterCardId: cardID) {
                let path = card.imageHighSrc?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? card.imageHighSrc!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : card.displayImageSrc
                embossedURL = AppConfiguration.imageURL(relativePath: path)
            } else {
                embossedURL = nil
            }
        } else {
            // Full card mode: use the selected card
            if let cardID = binder.embossedCardID,
               let card = await services.cardData.loadCard(masterCardId: cardID) {
                let path = card.imageHighSrc?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? card.imageHighSrc!.trimmingCharacters(in: .whitespacesAndNewlines)
                    : card.displayImageSrc
                embossedURL = AppConfiguration.imageURL(relativePath: path)
            } else {
                embossedURL = nil
            }
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
                .shadow(color: .black.opacity(0.75), radius: 2 * scale, x: 0, y: 1.5 * scale)
                .shadow(color: .black.opacity(0.50), radius: 8 * scale, x: 0, y: 4 * scale)

            let generatedSubtitle = "\(binder.slotList.count) \(binder.slotList.count == 1 ? "card" : "cards")"
            if let override = subtitleOverride {
                Text(override.uppercased())
                    .font(.system(size: 14 * scale, weight: .semibold, design: binder.titleFontStyleKind.fontDesign))
                    .tracking(2.0 * scale)
                    .foregroundStyle(titleTextStyle)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.75), radius: 2 * scale, x: 0, y: 1.5 * scale)
                    .shadow(color: .black.opacity(0.50), radius: 8 * scale, x: 0, y: 4 * scale)
            } else {
                Text(generatedSubtitle.uppercased())
                    .font(.system(size: 14 * scale, weight: .semibold, design: binder.titleFontStyleKind.fontDesign))
                    .tracking(2.0 * scale)
                    .foregroundStyle(titleTextStyle)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.75), radius: 2 * scale, x: 0, y: 1.5 * scale)
                    .shadow(color: .black.opacity(0.50), radius: 8 * scale, x: 0, y: 4 * scale)
            }
        }
        .padding(.horizontal, 8 * scale)
    }

    // MARK: - Value label (tinted serif at the bottom)

    private func valueLabel(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 44 * scale, weight: .bold, design: binder.titleFontStyleKind.fontDesign))
            .foregroundStyle(titleTextStyle)
            .shadow(color: .black.opacity(0.75), radius: 2 * scale, x: 0, y: 1.5 * scale)
            .shadow(color: .black.opacity(0.50), radius: 8 * scale, x: 0, y: 4 * scale)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8 * scale)
    }

    // MARK: - Spine overlay (left edge with binding rings)

    private func spineOverlay(scale: CGFloat) -> some View {
        GeometryReader { proxy in
            // Darkened spine strip
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(width: 32 * scale)

            // Binding rings/dots
            ZStack(alignment: .topLeading) {
                ForEach(Array(BinderRingGuide.normalizedYPositions.enumerated()), id: \.offset) { _, yPosition in
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
                        .position(x: 16 * scale, y: proxy.size.height * yPosition)
                }
            }
            .frame(width: 32 * scale)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Full bleed cover art layer

    private func fullBleedArtLayer(url: URL, geo: GeometryProxy, scale: CGFloat) -> some View {
        // Use cover frame size for the decode target size, scaled for retina display
        let targetSize = CGSize(width: geo.size.width * 2.0, height: geo.size.height * 2.0)

        return CachedAsyncImage(
            url: url,
            targetSize: targetSize
        ) { img in
            fullBleedArtLayer(image: img, geo: geo, scale: scale)
        } placeholder: {
            ProgressView().controlSize(.small).opacity(0.3)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func fullBleedArtLayer(image img: Image, geo: GeometryProxy, scale: CGFloat) -> some View {
        let isCharacter = binder.embossModeKind == .character
        
        return ZStack {
            img
                .resizable()
                .aspectRatio(contentMode: isCharacter ? .fit : .fill)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(isCharacter ? 1.15 : 1.0)
                .clipped()
            
            themeTintOverlay(geo: geo)
            
            BinderTextureView(
                baseColour: .clear,
                baseGradientColors: nil,
                texture: binder.textureKind,
                seed: binder.textureSeed,
                compact: compact
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: geo.size.height * 0.03, style: .continuous))
    }

    @ViewBuilder
    private func themeTintOverlay(geo: GeometryProxy) -> some View {
        let surfaceColor = BinderColourPalette.color(named: binder.colour)
        let gradientColors = BinderColourPalette.gradientColors(named: binder.colour)
        let colors = gradientColors ?? [surfaceColor, surfaceColor]
        
        let topColor = colors.first ?? surfaceColor
        let bottomColor = colors.last ?? surfaceColor
        
        let overlayGradient = LinearGradient(
            colors: [
                topColor.opacity(0.55),
                topColor.opacity(0.15),
                bottomColor.opacity(0.15),
                bottomColor.opacity(0.60)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        
        Rectangle()
            .fill(overlayGradient)
    }

    // MARK: - Peeking card thumbnail

    @ViewBuilder
    private func peekingCardImage(image: UIImage, scale: CGFloat, index: Int, totalCount: Int) -> some View {
        let middleIndex = Double(totalCount - 1) / 2.0
        let relativeIndex = Double(index) - middleIndex
        let rotation = relativeIndex * 15.0
        let xOffset = relativeIndex * 8 * scale
        let yOffset = abs(relativeIndex) * 12 * scale

        ZStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3 * scale, x: -2 * scale, y: 2 * scale)

            RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5 * scale)
        }
        .aspectRatio(5/7, contentMode: .fit)
        .rotationEffect(.degrees(rotation), anchor: .bottom)
        .offset(x: xOffset, y: yOffset)
        .zIndex(-Double(index))
    }

    @ViewBuilder
    private func peekingCard(url: URL, scale: CGFloat, index: Int, totalCount: Int) -> some View {
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
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 140 * scale, height: 196 * scale)) { img in
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
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

    private func placeholderPeekingCard(scale: CGFloat, index: Int, totalCount: Int) -> some View {
        let middleIndex = Double(totalCount - 1) / 2.0
        let relativeIndex = Double(index) - middleIndex
        let rotation = relativeIndex * 15.0
        let xOffset = relativeIndex * 8 * scale
        let yOffset = abs(relativeIndex) * 12 * scale
        let tint = BinderColourPalette.color(named: binder.colour)

        return RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
            .fill(
                LinearGradient(
                    colors: placeholderCardColors(tint: tint, index: index),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.8 * scale)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11 * scale, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(7 * scale)
            }
            .shadow(color: .black.opacity(0.25), radius: 3 * scale, x: -2 * scale, y: 2 * scale)
            .aspectRatio(5/7, contentMode: .fit)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .offset(x: xOffset, y: yOffset)
            .zIndex(-Double(index))
    }

    private func placeholderCardColors(tint: Color, index: Int) -> [Color] {
        if binder.colour == BinderColourPalette.logoColourName {
            let colors = BinderColourPalette.logoGradientColors
            return [
                colors[index % colors.count].opacity(0.90),
                colors[(index + 1) % colors.count].opacity(0.72),
                Color.white.opacity(0.55)
            ]
        }

        return [
            tint.opacity(0.72),
            tint.opacity(0.44),
            Color.white.opacity(0.50)
        ]
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

    /// Pre-decoded peeking card images for export snapshots.
    func peekingImagesOverride(_ images: [UIImage?]?) -> Self {
        var copy = self
        copy.peekingImagesOverride = images
        return copy
    }

    /// Pre-decoded embossed art for export snapshots.
    func embossedImageOverride(_ image: UIImage?) -> Self {
        var copy = self
        copy.embossedImageOverride = image
        return copy
    }
}
