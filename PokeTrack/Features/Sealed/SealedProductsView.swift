import SwiftData
import SwiftUI

struct SealedProductsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \SealedCollectionItem.addedAt, order: .reverse) private var owned: [SealedCollectionItem]

    @State private var showPaywall = false

    var body: some View {
        Group {
            if !services.store.isPremium {
                ContentUnavailableView(
                    "Premium only",
                    systemImage: "shippingbox",
                    description: Text("Upgrade to track sealed products.")
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Unlock") { showPaywall = true }
                    }
                }
            } else {
                List {
                    Section("Your sealed") {
                        if owned.isEmpty {
                            Text("No sealed items yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(owned, id: \.id) { item in
                                VStack(alignment: .leading) {
                                    Text(item.productName).font(.headline)
                                    Text("×\(item.quantity) · \(item.sealedState)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onDelete(perform: deleteOwned)
                        }
                    }

                    Section("Catalog") {
                        if let err = services.sealed.lastError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        } else if let catalog = services.sealed.catalog {
                            ForEach(catalog.products.prefix(100)) { p in
                                Button {
                                    addProduct(p)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(p.name)
                                            Text(p.type ?? "")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let gbp = services.sealed.gbpPrice(productId: p.id, usdToGbp: services.pricing.usdToGbp) {
                                            Text(String(format: "£%.2f", gbp))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("Loading catalog…")
                        }
                    }
                }
                .task {
                    await services.sealed.loadAll()
                }
            }
        }
        .navigationTitle("Sealed")
        .sheet(isPresented: $showPaywall) {
            PaywallSheet().environment(services)
        }
    }

    private func addProduct(_ p: SealedProductEntry) {
        let mapped = mapSealedType(p.type)
        let row = SealedCollectionItem(
            pokedataProductId: p.id,
            productName: p.name,
            productType: mapped,
            quantity: 1,
            sealedState: "sealed"
        )
        modelContext.insert(row)
    }

    private func deleteOwned(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(owned[i])
        }
    }

    private func mapSealedType(_ t: String?) -> String {
        guard let u = t?.uppercased() else { return "other" }
        switch u {
        case "BOOSTERPACK", "BLISTERPACK": return "booster-pack"
        case "ELITETRAINERBOX": return "elite-trainer-box"
        case "BOOSTERBOX": return "booster-box"
        case "COLLECTIONBOX", "COLLECTIONCHEST", "PINCOLLECTION": return "collection-box"
        case "TIN": return "tin"
        case "PREMIUMTRAINERBOX", "SPECIALBOX": return "premium-collection"
        default: return "other"
        }
    }
}
