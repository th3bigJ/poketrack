import SwiftUI
import UIKit

/// A premium representation of a binder cover, featuring procedural textures,
/// a reinforced spine, an ornamental tinted header, and an optional fan of
/// "peeking" card-back thumbnails. Designed in an A4 portrait ratio so it
/// reads as a real binder spine rather than a tile.
struct BinderCoverView: View {
    let title: String
    let subtitle: String?
    let colourName: String
    let texture: BinderTexture
    let seed: Int
    let peekingCardURLs: [URL?]

    /// When `false`, the card fan is omitted and the cover shows only the
    /// title (slightly larger, centred). User-facing toggle — the model stores
    /// this as ``Binder/showCardPreview``.
    var showCardPreview: Bool = true

    /// If true, the view uses smaller refinements suitable for list cells.
    var compact: Bool = false

    /// Optional formatted total value (e.g. "£1,779") rendered prominently at
    /// the bottom of the cover. Pass `nil` to omit (e.g. for empty binders or
    /// preview/creation flows where the value isn't meaningful yet).
    var valueText: String? = nil
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
    private var resolvedBinderColor: Color {
        BinderColourPalette.color(named: colourName)
    }
    /// Mix the binder's base colour into white at the given intensity. 0 → pure
    /// white, 1 → the raw binder colour. Small values (0.08–0.30) give us the
    /// "white with a hint of colour" look used on the cover text.
    private func tintedWhite(intensity: Double) -> Color {
        let ui = UIColor(resolvedBinderColor)
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
        titleTextColor == .gold ? defaultTitleAccent : titleTextColor.swiftUIColor
    }
    private var titleTextStyle: AnyShapeStyle {
        if titleTextColor == .gold {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [defaultTitleHighlight, defaultTitleAccent],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(titleTextColor.swiftUIColor)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Main binder body (tactile material)
            BinderTextureView(
                colourName: colourName,
                texture: texture,
                seed: seed,
                compact: compact
            )
            .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: compact ? 4 : 8, x: 0, y: 4)

            // Foreground content — ornament at top, title in upper portion,
            // optional card fan in the middle, value at the bottom.
            VStack(spacing: 0) {
                Spacer().frame(height: compact ? 14 : 22)

                topOrnament

                Spacer().frame(height: compact ? 10 : 14)

                titleBlock

                if showCardPreview && !peekingCardURLs.isEmpty {
                    Spacer(minLength: compact ? 6 : 10)

                    HStack(spacing: compact ? -35 : -50) {
                        ForEach(0..<peekingCardURLs.count, id: \.self) { index in
                            peekingCard(url: peekingCardURLs[index], index: index)
                        }
                    }

                    Spacer(minLength: compact ? 6 : 10)
                } else {
                    Spacer(minLength: 0)
                }

                if let valueText {
                    valueLabel(valueText)
                        .padding(.bottom, compact ? 16 : 24)
                } else {
                    Spacer().frame(height: compact ? 14 : 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, compact ? 22 : 36)
            .padding(.trailing, compact ? 10 : 14)

            // Spine overlay (stays on left)
            spineOverlay
        }
        .frame(maxWidth: .infinity)
        // A4-ish portrait ratio (1 : ~1.41). On the listing grid the cells are
        // ~160pt wide which gives ~226pt tall; the larger preview height keeps
        // the same proportion when the cover is shown full-screen.
        .frame(height: compact ? 230 : 320)
    }

    // MARK: - Top ornament (tinted line + diamond)

    private var topOrnament: some View {
        HStack(spacing: compact ? 6 : 10) {
            ornamentLine
            ornamentDiamond
            ornamentLine
        }
        .frame(maxWidth: compact ? 110 : 160)
    }

    private var ornamentLine: some View {
        LinearGradient(
            colors: [
                ornamentColor.opacity(0.0),
                ornamentColor.opacity(0.85),
                ornamentColor.opacity(0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: compact ? 1 : 1.4)
    }

    private var ornamentDiamond: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: titleTextColor == .gold
                    ? [defaultTitleHighlight, defaultTitleAccent]
                    : [ornamentColor.opacity(0.95), ornamentColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .rotationEffect(.degrees(45))
            .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
            .shadow(color: .black.opacity(0.4), radius: 0.5, x: 0, y: 0.5)
    }

    // MARK: - Title block (title + subtitle in tinted white)

    private var titleBlock: some View {
        VStack(spacing: compact ? 4 : 6) {
            Text(title.isEmpty ? "Binder name…" : title)
                .font(.system(size: compact ? 17 : 24, weight: .bold, design: titleFontStyle.fontDesign))
                .foregroundStyle(titleTextStyle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .opacity(title.isEmpty ? 0.5 : 1)
                .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 1)

            if let subtitle {
                Text(subtitle.uppercased())
                    .font(.system(size: compact ? 9.5 : 11.5, weight: .semibold, design: titleFontStyle.fontDesign))
                    .tracking(compact ? 1.4 : 1.8)
                    .foregroundStyle(titleTextColor == .gold ? defaultTitleAccent.opacity(0.85) : titleTextColor.swiftUIColor.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Value label (tinted serif at the bottom)

    private func valueLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: compact ? 26 : 38, weight: .bold, design: titleFontStyle.fontDesign))
            .foregroundStyle(titleTextStyle)
            .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 8)
    }

    // MARK: - Spine overlay (left edge with binding rings)

    private var spineOverlay: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Darkened spine strip
                Rectangle()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: compact ? 20 : 32)

                // Binding rings/dots
                VStack(spacing: compact ? 30 : 44) {
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
                .padding(.vertical, compact ? 24 : 36)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Peeking card thumbnail

    @ViewBuilder
    private func peekingCard(url: URL?, index: Int) -> some View {
        let cardCount = peekingCardURLs.count
        let middleIndex = Double(cardCount - 1) / 2.0
        let relativeIndex = Double(index) - middleIndex

        // Fanning geometry: cards rotate from the bottom centre to create
        // a natural "spread".
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
    init(binder: Binder, compact: Bool = false, valueText: String? = nil) {
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
            showCardPreview: binder.showCardPreview,
            compact: compact,
            valueText: valueText,
            titleTextColor: binder.titleTextColorKind,
            titleFontStyle: binder.titleFontStyleKind
        )
    }
}


#Preview {
    VStack(spacing: 20) {
        BinderCoverView(
            title: "Charizard Vault",
            subtitle: "RAW · 9 cards",
            colourName: "crimson",
            texture: .leather,
            seed: 1,
            peekingCardURLs: [nil, nil, nil],
            valueText: "£4,210"
        )
        .padding()

        BinderCoverView(
            title: "Blue Chip",
            subtitle: "RAW · 18 cards",
            colourName: "navy",
            texture: .suede,
            seed: 2,
            peekingCardURLs: [URL(string: "https://example.com/1.png"), nil, nil],
            compact: true,
            valueText: "£1,779"
        )
        .padding()
    }
    .background(Color.black)
}
