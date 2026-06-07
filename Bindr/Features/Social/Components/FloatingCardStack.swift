import SwiftUI

// MARK: - FloatingCardStack
//
// Hero animation for the Social landing & Onboarding screens — three
// "trading cards" floating with a gentle parallax + tilt loop. The stack
// has two render modes:
//
//   * `.gradient` — stylised gradient cards with rarity badges. Used
//     when the catalog hasn't loaded yet (very fresh installs) or in
//     pure-preview contexts. Zero network dependencies.
//   * `.realCards([Card])` — actual catalog cards with their real
//     `imageHighSrc` artwork loaded through `CachedAsyncImage` (so
//     offline pack + on-disk cache transparently kick in).
//
// Used in:
//   * `SocialLandingView` hero block
//   * `OnboardingSocialDiscoveryView` hero block
//
// Both call sites kick off `FeaturedHeroCardsLoader.loadFeaturedCards`
// and swap from gradient → real seamlessly as data arrives.

struct FloatingCardStack: View {
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var source: FloatingCardStackSource = .gradient(HeroCard.defaultTrio)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(faces.enumerated()), id: \.element.id) { index, face in
                    floatingFace(face: face, index: index, t: t)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Stable view-model used by the layout — both modes lower into this
    /// representation so the float/tilt math stays in one place.
    private var faces: [FloatingFace] {
        switch source {
        case .gradient(let cards):
            return cards.prefix(3).map { card in
                FloatingFace(
                    id: card.id.uuidString,
                    glow: card.glow,
                    body: .gradient(card)
                )
            }
        case .realCards(let cards):
            return cards.prefix(3).map { card in
                FloatingFace(
                    id: card.masterCardId,
                    glow: glowColor(for: card),
                    body: .real(card)
                )
            }
        }
    }

    private func floatingFace(face: FloatingFace, index: Int, t: TimeInterval) -> some View {
        // Each card gets a slightly different phase + amplitude so the
        // stack never feels like one rigid rotation.
        let phase = Double(index) * 1.7
        let bob = sin((t + phase) * 0.9) * 6
        let tilt = sin((t + phase) * 0.6) * 4
        let baseRotation: Double
        let xOffset: CGFloat
        let yOffset: CGFloat
        let scale: CGFloat
        switch index {
        case 0:
            baseRotation = -12; xOffset = -90; yOffset = 12; scale = 0.86
        case 1:
            baseRotation = 4;   xOffset = 6;   yOffset = -4; scale = 1.0
        default:
            baseRotation = 14;  xOffset = 92;  yOffset = 18; scale = 0.84
        }

        return HeroCardFace(face: face)
            .frame(width: 170, height: 240)
            .scaleEffect(scale)
            .rotationEffect(.degrees(baseRotation + tilt))
            .offset(x: xOffset, y: yOffset + bob)
            .shadow(color: face.glow.opacity(colorScheme == .dark ? 0.42 : 0.28), radius: 28, x: 0, y: 18)
    }

    /// Crude per-card glow tint inferred from rarity / element. Doesn't
    /// matter if it's slightly off — it's a backdrop, not the focal point.
    private func glowColor(for card: Card) -> Color {
        let rarity = (card.rarity ?? "").lowercased()
        if rarity.contains("hyper") { return Color(hex: "FF6F40") }
        if rarity.contains("rainbow") { return Color(hex: "A78BFA") }
        if rarity.contains("secret") { return Color(hex: "F7CD63") }
        if rarity.contains("manga") { return Color(hex: "EF1F2F") }
        if rarity.contains("illustration") { return Color(hex: "FFB02E") }
        if let element = card.elementTypes?.first?.lowercased() {
            switch element {
            case "fire":       return Color(hex: "FF6F40")
            case "water":      return Color(hex: "4FACFE")
            case "grass":      return Color(hex: "52C97C")
            case "lightning":  return Color(hex: "F7CD63")
            case "psychic":    return Color(hex: "A78BFA")
            case "darkness":   return Color(hex: "5B6478")
            case "metal":      return Color(hex: "8E9AAF")
            case "dragon":     return Color(hex: "B58A2C")
            case "fairy":      return Color(hex: "F08AB7")
            default: break
            }
        }
        return Color(hex: "A78BFA")
    }
}

// MARK: - Modes

/// Source of truth for what the stack should render. Keeps the call site
/// explicit — gradient or real cards, never a mishmash of half-loaded
/// state mixed with placeholder gradients.
enum FloatingCardStackSource {
    case gradient([HeroCard])
    case realCards([Card])
}

/// Layout-stage representation. The `.gradient` / `.real` distinction is
/// hidden from `floatingFace` so the geometry math stays in one place.
private struct FloatingFace: Identifiable {
    let id: String
    let glow: Color
    let body: FloatingFaceBody
}

private enum FloatingFaceBody {
    case gradient(HeroCard)
    case real(Card)
}

// MARK: - Face

private struct HeroCardFace: View {
    @Environment(\.colorScheme) private var colorScheme
    let face: FloatingFace

    var body: some View {
        switch face.body {
        case .gradient(let card):
            GradientHeroCardFace(card: card)
        case .real(let card):
            RealHeroCardFace(card: card)
        }
    }
}

// MARK: - Real card face

private struct RealHeroCardFace: View {
    @Environment(\.colorScheme) private var colorScheme
    let card: Card

    private var imageURL: URL? {
        // Prefer the high-res asset for a sharp foil look at hero scale,
        // fall back to the low-res so we never show an empty rectangle.
        if let hi = card.imageHighSrc?.trimmingCharacters(in: .whitespacesAndNewlines), !hi.isEmpty {
            return AppConfiguration.imageURL(relativePath: hi)
        }
        return AppConfiguration.imageURL(relativePath: card.displayImageSrc)
    }

    var body: some View {
        ZStack {
            // Dark backdrop so transparent / off-aspect catalog images
            // never reveal a flash of the page behind them.
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.55 : 0.35))

            CachedAsyncImage(
                url: imageURL,
                targetSize: CGSize(width: 340, height: 480),
                content: { image in
                    image
                        .resizable()
                        .scaledToFill()
                },
                placeholder: {
                    // Gentle shimmer placeholder while the image streams in.
                    LinearGradient(
                        colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous))

            // Holo overlay — same diagonal sweep we use on the gradient
            // face, but knocked back so it doesn't fight the artwork.
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            // Inner gloss highlight along the top edge so the card reads
            // as a glossy object rather than a photo pasted in.
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .stroke(Color.black.opacity(0.22), lineWidth: 0.5)
        }
    }
}

// MARK: - Gradient face

private struct GradientHeroCardFace: View {
    @Environment(\.colorScheme) private var colorScheme
    let card: HeroCard

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [card.gradientTop, card.gradientBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Inner gloss highlight
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.5), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .padding(0.5)

            // Holo overlay — radial shine moving along a diagonal axis
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: card.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(card.rarityBadge)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.22), in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()

                Text(card.title)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(BindrSpacing.md)
        }
        .overlay {
            // Hard edge stroke so the card reads as an object, not a swatch.
            RoundedRectangle(cornerRadius: BindrRadius.xl, style: .continuous)
                .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
        }
    }
}

// MARK: - Gradient model

struct HeroCard: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let rarityBadge: String
    let gradientTop: Color
    let gradientBottom: Color
    let glow: Color

    static let defaultTrio: [HeroCard] = [
        HeroCard(
            title: "Charizard ex",
            subtitle: "Scarlet & Violet • 199/198",
            symbol: "flame.fill",
            rarityBadge: "HYPER RARE",
            gradientTop: Color(hex: "FF7A3C"),
            gradientBottom: Color(hex: "C0351F"),
            glow: Color(hex: "FF6F40")
        ),
        HeroCard(
            title: "Moonbreon",
            subtitle: "Evolving Skies • 215/203",
            symbol: "moon.stars.fill",
            rarityBadge: "ALT ART",
            gradientTop: Color(hex: "2A1A4A"),
            gradientBottom: Color(hex: "0A0518"),
            glow: Color(hex: "A78BFA")
        ),
        HeroCard(
            title: "Charizard ex",
            subtitle: "Obsidian Flames • 125/197",
            symbol: "flame.fill",
            rarityBadge: "ULTRA RARE",
            gradientTop: Color(hex: "EF1F2F"),
            gradientBottom: Color(hex: "7B0E18"),
            glow: Color(hex: "FF4A57")
        )
    ]
}
