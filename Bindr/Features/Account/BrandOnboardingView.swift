import SwiftUI

/// First-run prompt: which TCG catalogs to enable (drives browse carousel + future sync scope).
struct BrandOnboardingView: View {
    @Environment(AppServices.self) private var services
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Turn on each game you want in your library. Pokémon is on by default; add other games from the list if you collect them. You can change this anytime in Account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                Section("Catalogs") {
                    ForEach(services.brandsManifest.orderedBrands) { brand in
                        Toggle(
                            brand.displayTitle,
                            isOn: Binding(
                                get: { services.brandSettings.enabledBrands.contains(brand) },
                                set: { services.brandSettings.setEnabled(brand, isOn: $0) }
                            )
                        )
                    }
                }
                Section {
                    Picker(
                        "Default browse tab",
                        selection: Binding(
                            get: { services.brandSettings.selectedCatalogBrand },
                            set: { services.brandSettings.selectedCatalogBrand = $0 }
                        )
                    ) {
                        ForEach(
                            services.brandsManifest.sortBrands(services.brandSettings.enabledBrands)
                        ) { b in
                            Text(b.displayTitle).tag(b)
                        }
                    }
                } footer: {
                    Text("This selects which cards appear on the Browse tab first. Switch anytime using the carousel.")
                }
            }
            .navigationTitle("Your collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        services.brandSettings.completeBrandOnboarding()
                        isPresented = false
                    }
                }
            }
        }
    }
}
