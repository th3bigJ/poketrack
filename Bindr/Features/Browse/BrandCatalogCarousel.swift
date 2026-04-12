import SwiftUI

/// Horizontal brand chips above the browse grid (Pokémon vs ONE PIECE TCG).
struct BrandCatalogCarousel: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let brands = services.brandSettings.enabledBrands.sorted(by: { $0.menuOrder < $1.menuOrder })
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(brands) { brand in
                    Button {
                        services.brandSettings.selectedCatalogBrand = brand
                    } label: {
                        brandChip(brand)
                    }
                    .buttonStyle(.plain)
                    // Identical tap + layout slots so different PNG aspect ratios can’t read as different sizes.
                    .frame(width: Self.brandSlot.width, height: Self.brandSlot.height)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card catalog brand")
    }

    /// Both logos are drawn in the **same** rectangle. `scaledToFit` left uneven empty space for wide vs tall PNGs;
    /// `scaledToFill` + clip fills that rectangle so on-screen footprint matches (edges may crop slightly).
    private static let brandSlot = CGSize(width: 140, height: 40)

    private func brandChip(_ brand: TCGBrand) -> some View {
        let selected = services.brandSettings.selectedCatalogBrand == brand
        return brandAssetImage(brand)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .scaledToFill()
            .frame(width: Self.brandSlot.width, height: Self.brandSlot.height)
            .clipped()
            .contentShape(Rectangle())
        .opacity(selected ? 1 : 0.45)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("\(brand.displayTitle) cards")
    }

    private func brandAssetImage(_ brand: TCGBrand) -> Image {
        switch brand {
        case .pokemon: Image("BrandPokemonLogo")
        case .onePiece: Image("BrandOnePieceLogo")
        }
    }
}
