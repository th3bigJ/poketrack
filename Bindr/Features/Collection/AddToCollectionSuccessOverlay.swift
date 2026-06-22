import SwiftUI

struct AddToCollectionSuccessContext {
    let card: Card
    let variantKey: String
    let variantLabel: String
    let gradeKey: String
}

struct AddToCollectionSuccessPresentation: Identifiable {
    let id = UUID()
    let card: Card
    let variantLabel: String
    let isSpecial: Bool
    let reasons: [String]

    var detailLine: String {
        if !reasons.isEmpty {
            return reasons.joined(separator: " + ")
        }
        return variantLabel
    }
}

@MainActor
func makeAddToCollectionSuccessPresentation(
    for context: AddToCollectionSuccessContext,
    services: AppServices
) async -> AddToCollectionSuccessPresentation {
    let marketUSD = await services.pricing.usdPriceForVariantAndGrade(
        for: context.card,
        variantKey: context.variantKey,
        grade: context.gradeKey
    )
    let isHighValue = (marketUSD ?? 0) >= 50
    let isWishlisted = services.wishlist?.isInWishlist(cardID: context.card.masterCardId, variantKey: context.variantKey) == true
        || services.wishlist?.isInWishlist(cardID: context.card.masterCardId) == true
    let isSpecialRarity = isCollectionCelebrationRarity(context.card.rarity)
    var reasons: [String] = []
    if isHighValue { reasons.append("High value") }
    if isWishlisted { reasons.append("Wishlisted") }
    if isSpecialRarity { reasons.append("Rare pull") }

    return AddToCollectionSuccessPresentation(
        card: context.card,
        variantLabel: context.variantLabel,
        isSpecial: !reasons.isEmpty,
        reasons: reasons
    )
}

private func isCollectionCelebrationRarity(_ rarity: String?) -> Bool {
    let normalized = rarity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    guard !normalized.isEmpty else { return false }
    let markers = [
        "illustration", "special", "secret", "ultra", "hyper", "rainbow", "gold",
        "shiny", "radiant", "amazing", "ace spec", "trainer gallery", "rare prime",
        "rare holo lv.x", "rare holo ex", "rare holo gx", "rare holo v", "rare holo vmax",
        "rare holo vstar", "manga", "alternate", "alt art", "parallel", "super rare",
        "double rare", "triple rare", "art rare", "sar", "sec", "sr", "hr", "ur"
    ]
    return markers.contains { normalized.contains($0) }
}

struct AddToCollectionSuccessOverlay: View {
    let presentation: AddToCollectionSuccessPresentation

    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppServices.self) private var services: AppServices?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardEntered = false
    @State private var shimmerTravel: CGFloat = -1.2
    @State private var burstExpanded = false

    private var isGradientTheme: Bool {
        services?.theme.isGradientThemeSelected == true
    }

    private var burstColors: [Color] {
        if isGradientTheme, let theme = services?.theme {
            return theme.activeGradientColors
        }
        return [accent, BindrPalette.binderGold, BindrPalette.ownedGreen]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.38 : 0.22)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    if presentation.isSpecial {
                        CollectionAddSpecialBurst(
                            isExpanded: burstExpanded,
                            reduceMotion: reduceMotion,
                            colors: burstColors
                        )
                    }

                    cardPreview
                        .frame(width: 176)
                        .scaleEffect(cardEntered ? 1 : 0.82)
                        .offset(y: cardEntered ? 0 : 170)
                        .opacity(cardEntered ? 1 : 0)
                }
                .frame(height: 260)

                VStack(spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(BindrPalette.ownedGreen)

                        Text("Added to collection")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                    }

                    Text(presentation.detailLine)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .bindrAccentStroke(accent.opacity(0.45), lineWidth: 1)
                }
                .scaleEffect(cardEntered ? 1 : 0.92)
                .opacity(cardEntered ? 1 : 0)
            }
            .padding(.horizontal, 28)
        }
        .allowsHitTesting(true)
        .onAppear(perform: play)
    }

    private var cardPreview: some View {
        ProgressiveAsyncImage(
            lowResURL: AppConfiguration.imageURL(relativePath: presentation.card.displayImageSrc),
            highResURL: presentation.card.imageHighSrc.map { AppConfiguration.imageURL(relativePath: $0) }
        ) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .aspectRatio(5 / 7, contentMode: .fit)
                .overlay {
                    Image(systemName: "rectangle.portrait")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
        .aspectRatio(5 / 7, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .bindrAccentStroke(accent.opacity(0.75), lineWidth: presentation.isSpecial ? 2 : 1.2)
        }
        .overlay {
            CollectionCardShimmer(progress: shimmerTravel)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .shadow(
            color: (presentation.isSpecial ? burstColors.last ?? accent : accent).opacity(colorScheme == .dark ? 0.42 : 0.24),
            radius: presentation.isSpecial ? 30 : 18,
            x: 0,
            y: 18
        )
    }

    private func play() {
        if reduceMotion {
            cardEntered = true
            shimmerTravel = 1.15
            burstExpanded = true
            return
        }

        withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
            cardEntered = true
        }
        withAnimation(.easeInOut(duration: 0.66).delay(0.14)) {
            shimmerTravel = 1.15
        }
        if presentation.isSpecial {
            withAnimation(.easeOut(duration: 0.78).delay(0.08)) {
                burstExpanded = true
            }
        }
    }
}

private struct CollectionCardShimmer: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.72),
                    Color.white.opacity(0.10),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: geo.size.width * 0.36, height: geo.size.height * 1.35)
            .rotationEffect(.degrees(18))
            .offset(x: progress * geo.size.width * 1.65, y: -geo.size.height * 0.16)
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
    }
}

private struct CollectionAddSpecialBurst: View {
    let isExpanded: Bool
    let reduceMotion: Bool
    let colors: [Color]

    private let particles: [CollectionBurstParticle] = [
        .init(symbol: "sparkle", x: -104, y: -84, size: 18, rotation: -26),
        .init(symbol: "star.fill", x: 92, y: -74, size: 15, rotation: 22),
        .init(symbol: "sparkle", x: -98, y: 78, size: 16, rotation: 18),
        .init(symbol: "circle.fill", x: 106, y: 70, size: 8, rotation: 0),
        .init(symbol: "diamond.fill", x: 0, y: -118, size: 10, rotation: 34),
        .init(symbol: "sparkle", x: 4, y: 112, size: 13, rotation: -12)
    ]

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: index == 0 ? 3 : 1.4
                    )
                    .frame(
                        width: isExpanded ? 210 + CGFloat(index * 38) : 92,
                        height: isExpanded ? 210 + CGFloat(index * 38) : 92
                    )
                    .opacity(isExpanded ? 0 : 0.46 - Double(index) * 0.08)
                    .blur(radius: index == 0 ? 0 : 0.8)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            colors.first?.opacity(0.34) ?? .clear,
                            colors.last?.opacity(0.18) ?? .clear,
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 150
                    )
                )
                .frame(width: isExpanded ? 300 : 120, height: isExpanded ? 300 : 120)
                .opacity(isExpanded ? 0.72 : 0.12)
                .blur(radius: 16)

            if !reduceMotion {
                ForEach(Array(particles.enumerated()), id: \.element.id) { index, particle in
                    Image(systemName: particle.symbol)
                        .font(.system(size: particle.size, weight: .bold))
                        .foregroundStyle(colors[index % max(colors.count, 1)])
                        .scaleEffect(isExpanded ? 1 : 0.25)
                        .rotationEffect(.degrees(isExpanded ? particle.rotation : 0))
                        .offset(x: isExpanded ? particle.x : 0, y: isExpanded ? particle.y : 0)
                        .opacity(isExpanded ? 0 : 1)
                }
            }
        }
        .frame(width: 320, height: 320)
        .allowsHitTesting(false)
    }
}

private struct CollectionBurstParticle: Identifiable {
    let id = UUID()
    let symbol: String
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let rotation: Double
}
