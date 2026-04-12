import StoreKit
import SwiftUI

struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Premium will unlock additional features as they ship. Catalog browsing uses your R2 data and public pricing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Purchase") {
                    if let product = services.store.products.first {
                        Button {
                            Task {
                                try? await services.store.purchase()
                                if services.store.isPremium { dismiss() }
                            }
                        } label: {
                            Text("\(product.displayName) — \(product.displayPrice)")
                        }
                    } else {
                        Text("Product not loaded. Configure In-App Purchases in App Store Connect for \(AppConfiguration.premiumProductID).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let err = services.store.purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Bindr Premium")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
