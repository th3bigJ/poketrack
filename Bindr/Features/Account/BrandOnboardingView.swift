import SwiftUI

/// First-run prompt: which TCG catalogs to enable (drives browse carousel + future sync scope).
struct BrandOnboardingView: View {
    @Environment(AppServices.self) private var services
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Turn on each game you want in your library. Pokémon is on by default; add ONE PIECE if you collect those cards. You can change this anytime in Account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                Section("Catalogs") {
                    ForEach(TCGBrand.allCases.sorted(by: { $0.menuOrder < $1.menuOrder })) { brand in
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
                            services.brandSettings.enabledBrands.sorted(by: { $0.menuOrder < $1.menuOrder })
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
