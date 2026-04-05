import SwiftData
import SwiftUI

struct WishlistView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Query(sort: \WishlistItem.addedAt, order: .reverse) private var items: [WishlistItem]

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "Wishlist empty",
                    systemImage: "heart",
                    description: Text("Add cards from the Cards tab.")
                )
            } else {
                List {
                    ForEach(items, id: \.id) { row in
                        NavigationLink {
                            WishlistDetailView(item: row)
                        } label: {
                            WishlistRowView(item: row)
                        }
                    }
                    .onDelete(perform: deleteRows)
                }
            }
        }
        .navigationTitle("Wishlist")
    }

    private func deleteRows(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(items[i])
        }
    }
}

struct WishlistRowView: View {
    @Environment(AppServices.self) private var services
    let item: WishlistItem

    var body: some View {
        HStack {
            if let c = services.cardData.card(masterCardId: item.masterCardId, setCode: item.setCode) {
                AsyncImage(url: AppConfiguration.imageURL(relativePath: c.imageLowSrc)) { p in
                    p.resizable().scaledToFit()
                } placeholder: {
                    Color.gray.opacity(0.15)
                }
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading) {
                    Text(c.cardName).font(.headline)
                    Text(item.setCode).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(item.masterCardId)
            }
        }
    }
}

struct WishlistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @Bindable var item: WishlistItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            if let card = services.cardData.card(masterCardId: item.masterCardId, setCode: item.setCode) {
                Section {
                    AsyncImage(url: AppConfiguration.imageURL(relativePath: card.imageLowSrc)) { p in
                        p.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(height: 200)
                    Text(card.cardName).font(.title2.bold())
                }
            }
            Section {
                Button("Remove", role: .destructive) {
                    modelContext.delete(item)
                    dismiss()
                }
            }
        }
        .navigationTitle("Wishlist item")
    }
}
