import SwiftUI

/// Shows enabled catalogs in a single row: **selected brand is always centered** (with neighbors on the sides when there are 3+ games). Logos scale to fit the available width.
struct BrandCatalogCarousel: View {
    @Environment(AppServices.self) private var services

    private var ordered: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    private var selected: TCGBrand {
        services.brandSettings.selectedCatalogBrand
    }

    var body: some View {
        let n = ordered.count
        Group {
            if n >= 3 {
                tripleSlotRow
            } else if n == 2 {
                twoSlotRow
            } else {
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card catalog brand, \(selected.displayTitle)")
    }

    // MARK: - 3+ brands: previous | selected | next (circular)

    private var tripleSlotRow: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let gap: CGFloat = 10
            let slotW = max(0, (w - gap * 2) / 3)
            let triple = neighborTriple(ordered: ordered, selected: selected)
            HStack(spacing: gap) {
                brandSlot(brand: triple.left, slotWidth: slotW, role: .side) {
                    select(triple.left)
                }
                brandSlot(brand: triple.center, slotWidth: slotW, role: .center) {
                    select(triple.center)
                }
                brandSlot(brand: triple.right, slotWidth: slotW, role: .side) {
                    select(triple.right)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: Self.rowHeight)
    }

    private func neighborTriple(ordered: [TCGBrand], selected: TCGBrand) -> (left: TCGBrand, center: TCGBrand, right: TCGBrand) {
        let n = ordered.count
        guard n >= 3 else {
            let only = ordered.first ?? .pokemon
            return (only, only, only)
        }
        let i = ordered.firstIndex(of: selected) ?? 0
        let center = ordered[i]
        let left = ordered[(i - 1 + n) % n]
        let right = ordered[(i + 1) % n]
        return (left, center, right)
    }

    // MARK: - 2 brands: equal split, selected emphasized

    private var twoSlotRow: some View {
        GeometryReader { geo in
            let gap: CGFloat = 12
            let slotW = max(0, (geo.size.width - gap) / 2)
            HStack(spacing: gap) {
                ForEach(ordered) { brand in
                    Button {
                        select(brand)
                    } label: {
                        brandLogo(brand: brand, emphasized: brand == selected)
                            .frame(width: slotW, height: Self.rowHeight - 8)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(brand == selected ? [.isSelected] : [])
                    .accessibilityLabel("\(brand.displayTitle) cards")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: Self.rowHeight)
    }

    private enum SlotRole {
        case center
        case side
    }

    private func brandSlot(brand: TCGBrand, slotWidth: CGFloat, role: SlotRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            brandLogo(brand: brand, emphasized: role == .center)
                .frame(width: slotWidth, height: role == .center ? Self.rowHeight - 4 : Self.rowHeight - 10)
        }
        .buttonStyle(.plain)
        .frame(width: slotWidth)
        .accessibilityAddTraits(brand == selected ? [.isSelected] : [])
        .accessibilityLabel(role == .center ? "\(brand.displayTitle), current catalog" : "Switch to \(brand.displayTitle)")
    }

    private func brandLogo(brand: TCGBrand, emphasized: Bool) -> some View {
        brandAssetImage(brand)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFit()
            .scaleEffect(emphasized ? 1.0 : 0.88, anchor: .center)
            .opacity(emphasized ? 1 : 0.42)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: emphasized)
            .animation(.spring(response: 0.38, dampingFraction: 0.82), value: brand)
    }

    private func brandAssetImage(_ brand: TCGBrand) -> Image {
        switch brand {
        case .pokemon: Image("BrandPokemonLogo")
        case .onePiece: Image("BrandOnePieceLogo")
        case .lorcana: Image("lorcana")
        }
    }

    private func select(_ brand: TCGBrand) {
        guard brand != services.brandSettings.selectedCatalogBrand else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
            services.brandSettings.selectedCatalogBrand = brand
        }
        HapticManager.selection()
    }

    private static let rowHeight: CGFloat = 48
}
