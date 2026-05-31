import SwiftUI

struct TradeWallView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.bindrAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Binding var navigationPath: NavigationPath

    @State private var cardEntries: [WallEntry] = []
    @State private var sealedEntries: [SealedWallEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cardDetailSession: CardDetailSession?
    @State private var selectedSealedProduct: SealedProduct?
    @State private var selectedTab: Tab = .cards

    enum Tab: String, CaseIterable {
        case cards  = "Cards"
        case sealed = "Sealed"
    }

    struct WallEntry: Identifiable {
        let id: String
        let card: Card
        let owner: SocialProfile
        var setName: String?
    }

    struct SealedWallEntry: Identifiable {
        let id: String
        let product: SealedProduct
        let owner: SocialProfile
    }

    private struct CardDetailSession: Identifiable {
        let id = UUID()
        let card: Card
        let owner: SocialProfile
    }

    var body: some View {
        VStack(spacing: 0) {
            if !cardEntries.isEmpty || !sealedEntries.isEmpty {
                tabPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }

            Group {
                if isLoading && cardEntries.isEmpty && sealedEntries.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    switch selectedTab {
                    case .cards:
                        if cardEntries.isEmpty {
                            emptyState(
                                icon: "square.stack.3d.up",
                                title: "No cards on the trade wall",
                                message: "Cards your friends have on their trade list will appear here."
                            )
                        } else {
                            ScrollView {
                                cardGrid
                                    .padding(.top, 4)
                            }
                        }
                    case .sealed:
                        if sealedEntries.isEmpty {
                            emptyState(
                                icon: "shippingbox",
                                title: "No sealed products on the trade wall",
                                message: "Sealed products your friends have on their trade list will appear here."
                            )
                        } else {
                            ScrollView {
                                sealedGrid
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await load() }
        .sheet(item: $cardDetailSession) { session in
            CardDetailSheet(
                cards: [session.card],
                startIndex: 0,
                tradeAction: { card, _ in startTrade(card: card, with: session.owner) },
                tradeActionLabel: "Offer Trade..."
            )
            .environment(services)
        }
        .sheet(item: $selectedSealedProduct) { product in
            SealedProductBrowseDetailView(products: [product], startProductID: product.id)
                .environment(services)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TradeWallTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    accent: accent,
                    action: {
                        Haptics.selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    }
                )
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 4, x: 0, y: 2)
    }

    // MARK: - Grids

    private var cardGrid: some View {
        EagerVGrid(items: cardEntries, columns: 2, spacing: 12) { entry in
            Button {
                Haptics.lightImpact()
                cardDetailSession = CardDetailSession(card: entry.card, owner: entry.owner)
            } label: {
                TradeWallCardCell(entry: entry, colorScheme: colorScheme)
            }
            .buttonStyle(TradeWallCellButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var sealedGrid: some View {
        EagerVGrid(items: sealedEntries, columns: 2, spacing: 12) { entry in
            Button {
                Haptics.lightImpact()
                selectedSealedProduct = entry.product
            } label: {
                TradeWallSealedCell(entry: entry, colorScheme: colorScheme)
            }
            .buttonStyle(TradeWallCellButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.08))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent.gradient)
            }
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
    }

    // MARK: - Load

    private func load() async {
        guard case .signedIn = services.socialAuth.authState else { return }
        isLoading = true
        defer { isLoading = false }

        await services.sealedProducts.loadFromLocalIfAvailable()

        do {
            let friends = try await services.socialFriend.fetchFriends()
            guard !friends.isEmpty else { return }

            let friendIDs = friends.map(\.id)
            let tradeListMap = try await services.socialCardLibrary.fetchTradeListCardIDsByUser(for: friendIDs)

            var newCardEntries: [WallEntry] = []
            var newSealedEntries: [SealedWallEntry] = []

            for friend in friends {
                let cardIDs = tradeListMap[friend.id] ?? []
                for cardID in cardIDs {
                    if let productID = SealedProduct.parseCollectionProductID(cardID) {
                        if let product = services.sealedProducts.products.first(where: { $0.id == productID }) {
                            newSealedEntries.append(SealedWallEntry(
                                id: "\(friend.id)-\(cardID)",
                                product: product,
                                owner: friend
                            ))
                        }
                    } else if let card = await services.cardData.loadCard(masterCardId: cardID) {
                        let setName = services.cardData.sets.first { $0.setCode == card.setCode }?.name
                        newCardEntries.append(WallEntry(
                            id: "\(friend.id)-\(cardID)",
                            card: card,
                            owner: friend,
                            setName: setName
                        ))
                    }
                }
            }

            cardEntries = newCardEntries
            sealedEntries = newSealedEntries
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Trade

    private func startTrade(card: Card, with friend: SocialProfile) {
        cardDetailSession = nil
        let item = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: friend.id,
            cardID: card.masterCardId,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )
        navigationPath.append(SocialDestination.tradeBuilder(
            receiverID: friend.id,
            theirCards: [item],
            myCards: []
        ))
    }
}

// MARK: - TradeWallTabButton

struct TradeWallTabButton: View {
    let tab: TradeWallView.Tab
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab == .cards ? "square.stack.3d.up" : "shippingbox")
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(isSelected ? .white : .primary.opacity(0.60))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isSelected ? accent.gradient : Color.clear.gradient, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TradeWallCardCell

/// Premium 2-column card cell. Card image fills the top ~72% of the cell;
/// the owner strip lives in a `.thinMaterial` footer below it — no cramped
/// corner overlays, name never truncates, avatar is large enough to see.
private struct TradeWallCardCell: View {
    let entry: TradeWallView.WallEntry
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Card image — Pokemon cards are ~245×342, i.e. roughly 5:7
            CachedAsyncImage(url: AppConfiguration.imageURL(relativePath: entry.card.displayImageSrc)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
            }
            .aspectRatio(5/7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()

            // Owner + card name footer
            ownerFooter
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08),
                    lineWidth: 0.5
                )
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.32 : 0.10),
            radius: 8, x: 0, y: 4
        )
    }

    private var ownerFooter: some View {
        HStack(spacing: 9) {
            ProfileAvatarView(profile: entry.owner, size: 32)
                .overlay(
                    Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.owner.displayName ?? entry.owner.username)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.card.cardName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        // Fixed footer height ensures both cells in a row are always the same
        // total height (image aspect ratio is already deterministic by column width).
        .frame(minHeight: 68, alignment: .top)
    }
}

// MARK: - TradeWallSealedCell

private struct TradeWallSealedCell: View {
    let entry: TradeWallView.SealedWallEntry
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Sealed box art — roughly square
            CachedAsyncImage(url: entry.product.imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .overlay {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
            }
            .aspectRatio(5/7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()

            ownerFooter
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08),
                    lineWidth: 0.5
                )
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.32 : 0.10),
            radius: 8, x: 0, y: 4
        )
    }

    private var ownerFooter: some View {
        HStack(spacing: 9) {
            ProfileAvatarView(profile: entry.owner, size: 32)
                .overlay(
                    Circle().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.owner.displayName ?? entry.owner.username)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(entry.product.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 68, alignment: .top)
    }
}

// MARK: - TradeWallCellButtonStyle

/// Scale-press feedback without the default opacity flash that `.plain` gives.
private struct TradeWallCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
