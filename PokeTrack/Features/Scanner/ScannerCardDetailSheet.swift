import SwiftUI

// MARK: - Expanded bar content (shared)

/// Card art + set line + pricing — used by the expanded `ScanResultBar` in the scanner.
struct ScannerResultExpandedContent: View {
    let card: Card
    /// Extra top padding when embedded in layouts that need it.
    var topPadding: CGFloat = 0

    @State private var imageScale: CGFloat = 0.92

    var body: some View {
        VStack(spacing: 0) {
            cardImageSection
                .padding(.top, topPadding)

            VStack(spacing: 4) {
                Text(card.setCode.uppercased() + " · #" + card.cardNumber)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                if let rarity = card.rarity {
                    Text(rarity)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.top, 16)

            pricingCard
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
        .onAppear {
            imageScale = 0.92
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.05)) {
                imageScale = 1.0
            }
        }
        .onChange(of: card.masterCardId) { _, _ in
            imageScale = 0.92
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                imageScale = 1.0
            }
        }
    }

    private var cardImageSection: some View {
        let screenWidth = UIScreen.main.bounds.width
        let width = min(screenWidth - 48, 320)
        let height = width * 1.395

        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: width, height: height)
            ProgressiveAsyncImage(
                lowResURL: AppConfiguration.imageURL(relativePath: card.imageLowSrc),
                highResURL: card.imageHighSrc.map { AppConfiguration.imageURL(relativePath: $0) }
            ) {
                Color.clear
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
        .scaleEffect(imageScale)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var pricingCard: some View {
        VStack(spacing: 0) {
            CardPricingPanel(card: card)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
