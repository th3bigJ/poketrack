import SwiftUI

struct CardActionMenu: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let card: Card
    let isOwned: Bool
    let isWishlisted: Bool
    let tradeActionLabel: String?
    
    // Actions
    let onSaveToCollection: () -> Void
    let onAddToWishlist: () -> Void
    let onRemoveFromWishlist: () -> Void
    let onAddToFolder: () -> Void
    let onTradeAction: (() -> Void)?
    let onShareAction: () -> Void
    let onEditAction: (() -> Void)?
    let onToggleTradeable: (() -> Void)?
    let onRemoveFromCollection: (() -> Void)?
    let isTradeable: Bool
    var onAddToDeck: (() -> Void)? = nil
    
    @State private var isMenuExpanded = false
    
    // Exact colors from CardDetailSheet
    private struct Palette {
        static let success = Color(red: 0.22, green: 0.81, blue: 0.44)
        static let chartLine = Color(red: 0.52, green: 0.44, blue: 0.94)
        static let gold = Color(red: 0.98, green: 0.78, blue: 0.18)
        static let folder = Color(red: 0.18, green: 0.72, blue: 0.88)
        static let share = Color(red: 0.36, green: 0.61, blue: 0.97)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Primary Action Button (Add to / Manage / Trade)
            primaryActionButton
            
            // Share Button (Kept separate as requested)
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
        .padding(.horizontal, 4)
        .overlay {
            if isMenuExpanded {
                // Full screen dismissal layer
                Color.black.opacity(0.001)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isMenuExpanded = false
                        }
                    }
                    .frame(width: 1000, height: 2000) // Large enough to cover screen
                    .offset(y: -500) // Center it roughly
            }
        }
        .overlay(alignment: .bottom) {
            if isMenuExpanded {
                glassMenuOverlay
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                        removal: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity).combined(with: .move(edge: .bottom))
                    ))
                    .offset(y: -74)
            }
        }
    }
    
    private var primaryActionButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isMenuExpanded.toggle()
            }
            Haptics.lightImpact()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 18, weight: .bold))
                
                Text(primaryLabel)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .fixedSize()
                
                Spacer()
                
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.4)
                    .rotationEffect(.degrees(isMenuExpanded ? 180 : 0))
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(primaryColor)
            .glassCardStyle(cornerRadius: 18, interactive: true)
        }
        .buttonStyle(.plain)
    }
    
    private var glassMenuOverlay: some View {
        VStack(spacing: 0) {
            ForEach(menuItems) { item in
                Button {
                    Haptics.selectionChanged()
                    item.action()
                    withAnimation(.spring(response: 0.25)) { isMenuExpanded = false }
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(item.color)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            if let sub = item.subLabel {
                                Text(sub)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if item.id != menuItems.last?.id {
                    Divider()
                        .padding(.horizontal, 20)
                        .opacity(0.06)
                }
            }
        }
        .frame(width: 280)
        .glassCardStyle(cornerRadius: 26, interactive: true)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.15), radius: 25, y: 15)
        .zIndex(100)
    }
    
    // MARK: - Logic
    
    private var primaryLabel: String {
        if isOwned { return "Manage..." }
        if tradeActionLabel != nil { return "Interested?" }
        return "Add to..."
    }
    
    private var primaryIcon: String {
        if isOwned { return "folder.fill" }
        if tradeActionLabel != nil { return "arrow.left.arrow.right.circle.fill" }
        return "plus.circle.fill"
    }
    
    private var primaryColor: Color {
        if isOwned { return Palette.share }
        if tradeActionLabel != nil { return Palette.chartLine }
        return Palette.success
    }
    
    private var menuItems: [MenuItem] {
        var items: [MenuItem] = []
        
        if isOwned {
            // COLLECTION MODE terminology
            items.append(MenuItem(
                label: "Add to Folder",
                subLabel: "Place this card in a folder",
                icon: "folder.badge.plus",
                color: Palette.folder,
                action: onAddToFolder
            ))
            
            if let _ = onTradeAction {
                items.append(MenuItem(
                    label: isTradeable ? "Remove from Trade List" : "Add to Trade List",
                    subLabel: isTradeable ? "Currently marked for trade" : "Add to your public trade list",
                    icon: isTradeable ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle",
                    color: Palette.chartLine,
                    action: { onTradeAction?() }
                ))
            }
            
            items.append(MenuItem(
                label: "Edit Details",
                subLabel: "Condition, price, and notes",
                icon: "pencil.circle",
                color: .primary.opacity(0.7),
                action: { onEditAction?() }
            ))
            
            if let onRemove = onRemoveFromCollection {
                items.append(MenuItem(
                    label: "Remove",
                    subLabel: "Delete from collection",
                    icon: "trash",
                    color: Color(red: 0.9, green: 0.3, blue: 0.3),
                    action: onRemove
                ))
            }
        } else {
            // BROWSE / SOCIAL MODE terminology
            
            // Context-aware Trade Action (e.g. from Trade Wall)
            if let label = tradeActionLabel, let action = onTradeAction {
                items.append(MenuItem(
                    label: label.replacingOccurrences(of: "...", with: ""),
                    subLabel: "Propose a deal for this card",
                    icon: "arrow.left.arrow.right.circle.fill",
                    color: Palette.chartLine,
                    action: action
                ))
            } else {
                // Standard Browse Mode
                items.append(MenuItem(
                    label: "Collection",
                    subLabel: "Add to your main collection",
                    icon: "plus.circle.fill",
                    color: Palette.success,
                    action: onSaveToCollection
                ))
            }
            
            items.append(MenuItem(
                label: "Wish List",
                subLabel: isWishlisted ? "Already wishlisted" : "Add to your wish list",
                icon: isWishlisted ? "star.fill" : "star",
                color: Palette.gold,
                action: isWishlisted ? onRemoveFromWishlist : onAddToWishlist
            ))
            
            items.append(MenuItem(
                label: "Add to Folder",
                subLabel: "Save to a specific folder",
                icon: "folder.badge.plus",
                color: Palette.folder,
                action: onAddToFolder
            ))

            if let onAddToDeck {
                items.append(MenuItem(
                    label: "Add to Deck",
                    subLabel: "Add this card to the deck",
                    icon: "rectangle.stack.badge.plus",
                    color: Color(red: 0.52, green: 0.44, blue: 0.94),
                    action: onAddToDeck
                ))
            }
        }

        return items
    }
}

private struct MenuItem: Identifiable {
    let id = UUID()
    let label: String
    let subLabel: String?
    let icon: String
    let color: Color
    let action: () -> Void
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            CardActionMenu(
                card: previewCard,
                isOwned: false,
                isWishlisted: false,
                tradeActionLabel: nil,
                onSaveToCollection: {},
                onAddToWishlist: {},
                onRemoveFromWishlist: {},
                onAddToFolder: {},
                onTradeAction: nil,
                onShareAction: {},
                onEditAction: {},
                onToggleTradeable: {},
                onRemoveFromCollection: {},
                isTradeable: false
            )
            
            CardActionMenu(
                card: previewCard,
                isOwned: true,
                isWishlisted: false,
                tradeActionLabel: nil,
                onSaveToCollection: {},
                onAddToWishlist: {},
                onRemoveFromWishlist: {},
                onAddToFolder: {},
                onTradeAction: nil,
                onShareAction: {},
                onEditAction: {},
                onToggleTradeable: {},
                onRemoveFromCollection: {},
                isTradeable: true
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
