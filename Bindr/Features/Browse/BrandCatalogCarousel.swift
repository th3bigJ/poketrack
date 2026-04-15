import SwiftUI

/// Shows enabled catalogs as a segmented picker using brand names.
struct BrandCatalogCarousel: View {
    @Environment(AppServices.self) private var services

    private var ordered: [TCGBrand] {
        services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
    }

    var body: some View {
        Picker("Catalog brand", selection: selectionBinding) {
            ForEach(ordered) { brand in
                Text(brand.displayTitle).tag(brand)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Card catalog brand")
    }

    private var selectionBinding: Binding<TCGBrand> {
        Binding(
            get: { services.brandSettings.selectedCatalogBrand },
            set: { brand in
                guard brand != services.brandSettings.selectedCatalogBrand else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    services.brandSettings.selectedCatalogBrand = brand
                }
                HapticManager.selection()
            }
        )
    }
}
