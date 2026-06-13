import SwiftUI

struct CardActionMenu: View {
    let isOwned: Bool
    let isWishlisted: Bool
    var availableVariantKeys: [String] = ["normal"]
    let card: Card

    let onSaveToCollection: (String) -> Void
    let onRemoveFromCollection: () -> Void
    let onAddToWishlist: () -> Void
    let onRemoveFromWishlist: () -> Void
    let onShareAction: () -> Void
    var collectionSuccessTrigger: Int = 0
    var wishlistSuccessTrigger: Int = 0

    private struct Palette {
        static let success = Color(red: 0.22, green: 0.81, blue: 0.44)
        static let danger = Color(red: 1.0, green: 0.36, blue: 0.34)
        static let gold = Color(red: 0.98, green: 0.78, blue: 0.18)
        static let share = Color(red: 0.36, green: 0.61, blue: 0.97)
    }

    private var singleVariantKey: String? {
        availableVariantKeys.count == 1 ? availableVariantKeys[0] : nil
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                wishlistButton

                HStack(spacing: 8) {
                    addCollectionButton
                    if isOwned {
                        removeCollectionButton
                    }
                }
                .frame(maxWidth: .infinity)

                shareButton
            }
            .padding(.horizontal, 4)
        }
    }

    private var wishlistButton: some View {
        Button(action: wishlistAction) {
            Image(systemName: isWishlisted ? "star.fill" : "star")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.gold)
                .frame(width: 56, height: 56)
                .glassCardStyle(cornerRadius: 18, interactive: true)
        }
        .buttonStyle(.plain)
        .bindrSuccessSpark(trigger: wishlistSuccessTrigger)
        .accessibilityLabel(isWishlisted ? "Remove from Wish List" : "Add to Wish List")
    }

    private var shareButton: some View {
        Button(action: onShareAction) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.share)
                .frame(width: 56, height: 56)
                .glassCardStyle(cornerRadius: 18, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
    }

    @ViewBuilder
    private var addCollectionButton: some View {
        if let variantKey = singleVariantKey {
            collectionButton(
                title: "Collection",
                systemImage: "plus.circle.fill",
                tint: Palette.success,
                action: { onSaveToCollection(variantKey) },
                successTrigger: collectionSuccessTrigger
            )
        } else {
            Menu {
                Section("Select Variant") {
                    ForEach(availableVariantKeys, id: \.self) { key in
                        Button { onSaveToCollection(key) } label: {
                            Text(variantLabel(key))
                        }
                    }
                }
            } label: {
                collectionButtonLabel(
                    title: "Collection",
                    systemImage: "plus.circle.fill",
                    tint: Palette.success
                )
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .bindrSuccessSpark(trigger: collectionSuccessTrigger)
        }
    }

    private var removeCollectionButton: some View {
        collectionButton(
            title: "Collection",
            systemImage: "minus.circle.fill",
            tint: Palette.danger,
            action: onRemoveFromCollection
        )
    }

    private func collectionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void,
        successTrigger: Int = 0
    ) -> some View {
        Button {
            Haptics.lightImpact()
            action()
        } label: {
            collectionButtonLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .bindrSuccessSpark(trigger: successTrigger)
        .accessibilityLabel("\(systemImage.contains("plus") ? "Add to" : "Remove from") collection")
    }

    private func collectionButtonLabel(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .glassCardStyle(cornerRadius: 18, interactive: true)
    }

    private func wishlistAction() {
        if isWishlisted {
            onRemoveFromWishlist()
        } else {
            onAddToWishlist()
        }
    }

    private func variantLabel(_ key: String) -> String {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != "normal" else { return "Normal" }
        let spaced = normalized
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            CardActionMenu(
                isOwned: false,
                isWishlisted: false,
                card: previewCard,
                onSaveToCollection: { _ in },
                onRemoveFromCollection: {},
                onAddToWishlist: {},
                onRemoveFromWishlist: {},
                onShareAction: {}
            )

            CardActionMenu(
                isOwned: true,
                isWishlisted: true,
                card: previewCard,
                onSaveToCollection: { _ in },
                onRemoveFromCollection: {},
                onAddToWishlist: {},
                onRemoveFromWishlist: {},
                onShareAction: {}
            )
        }
        .padding()
    }
}

private let previewCard = Card(
    masterCardId: "test",
    externalId: nil,
    tcgdex_id: nil,
    localId: nil,
    setCode: "TWM",
    setTcgdexId: nil,
    cardNumber: "1",
    cardName: "Perrin",
    fullDisplayName: nil,
    rarity: "Special Illustration Rare",
    category: "Pokemon",
    stage: nil,
    hp: nil,
    elementTypes: nil,
    dexIds: nil,
    subtypes: nil,
    trainerType: nil,
    energyType: nil,
    regulationMark: nil,
    evolveFrom: nil,
    artist: nil,
    imageLowSrc: "",
    imageHighSrc: nil,
    attacks: nil,
    abilities: nil,
    rules: nil,
    subtype: nil,
    weakness: nil,
    resistance: nil,
    retreatCost: nil,
    flavorText: nil,
    pricingVariants: nil
)
