import SwiftUI
import SwiftData

struct WishlistView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WishlistItem.dateAdded, order: .reverse) private var items: [WishlistItem]
    
    @State private var showPaywall = false
    @State private var showAddCard = false
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            // iCloud sync status section
            if !services.cloudSettings.isICloudAvailable {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud not available")
                                .font(.headline)
                            Text("Sign into iCloud to sync your wishlist across devices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // Wishlist items
            Section {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No wishlist items",
                        systemImage: "star.slash",
                        description: Text("Cards you want to collect will appear here")
                    )
                } else {
                    ForEach(items) { item in
                        WishlistItemRow(item: item)
                    }
                    .onDelete(perform: deleteItems)
                }
            } header: {
                HStack {
                    Text("Wishlist")
                    Spacer()
                    if !services.store.isPremium {
                        Text("\(items.count)/\(WishlistService.freeWishlistLimit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if !services.store.isPremium && items.count >= WishlistService.freeWishlistLimit {
                    Button("Upgrade to Premium for unlimited wishlist items") {
                        showPaywall = true
                    }
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Wishlist")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let wishlistService = services.wishlist else { return }
                    
                    if wishlistService.canAddItem {
                        showAddCard = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Add Card", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddCard) {
            AddToWishlistSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            // Initialize wishlist service with model context
            services.setupWishlist(modelContext: modelContext)
        }
    }
    
    private func deleteItems(at offsets: IndexSet) {
        guard let wishlistService = services.wishlist else { return }
        
        for index in offsets {
            let item = items[index]
            do {
                try wishlistService.removeItem(item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Wishlist Item Row

struct WishlistItemRow: View {
    @Environment(AppServices.self) private var services
    let item: WishlistItem
    
    @State private var cardDetails: CardDetails?
    
    var body: some View {
        HStack(spacing: 12) {
            // Card image placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 60, height: 84)
                .overlay {
                    if let cardDetails {
                        // You'd load actual image here
                        Text(cardDetails.number)
                            .font(.caption)
                    } else {
                        ProgressView()
                    }
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(cardDetails?.name ?? item.cardID)
                    .font(.headline)
                
                if let cardDetails {
                    Text(cardDetails.setName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Show market price if available
                    if let price = cardDetails.marketPrice {
                        Text(formatPrice(price))
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
                
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(item.variantKey)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Text("Added \(item.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
        }
        .task {
            await loadCardDetails()
        }
    }
    
    private func loadCardDetails() async {
        // Load card details from your existing CardDataService
        // This is just a placeholder - integrate with your actual card loading logic
        cardDetails = await services.cardData.loadCardDetails(cardID: item.cardID)
    }
    
    private func formatPrice(_ usd: Double) -> String {
        services.priceDisplay.currency.format(
            amountUSD: usd,
            usdToGbp: services.pricing.usdToGbp
        )
    }
}

// MARK: - Add to Wishlist Sheet

struct AddToWishlistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    
    @State private var cardID: String = ""
    /// Scrydex-style key, e.g. `normal`, `holofoil` (matches card pricing JSON).
    @State private var variantKey: String = "normal"
    @State private var notes: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    TextField("Card ID (e.g., sv3pt5-1)", text: $cardID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Variant (e.g. normal, holofoil)", text: $variantKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    // TODO: Add card search/picker here
                }
                
                Section("Notes (Optional)") {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add to Wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addToWishlist()
                    }
                    .disabled(cardID.isEmpty)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private func addToWishlist() {
        guard let wishlistService = services.wishlist else { return }
        
        do {
            try wishlistService.addItem(
                cardID: cardID.trimmingCharacters(in: .whitespaces),
                variantKey: variantKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "normal" : variantKey.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview Helpers

extension CardDataService {
    // Placeholder - implement this with your actual card loading logic
    func loadCardDetails(cardID: String) async -> CardDetails? {
        // Your existing card loading logic here
        return nil
    }
}

struct CardDetails {
    let name: String
    let number: String
    let setName: String
    let marketPrice: Double?
}

#Preview("Empty Wishlist") {
    NavigationStack {
        WishlistView()
            .environment(AppServices())
            .modelContainer(for: [WishlistItem.self, CollectionItem.self, TransactionRecord.self])
    }
}
