import SwiftUI
import SwiftData

struct FoldersListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]
    @State private var folderValueByID: [UUID: Double] = [:]
    @State private var folderToEdit: CardFolder? = nil
    @State private var editedFolderTitle: String = ""

    private var folderValueSignature: String {
        folders
            .map { folder in
                let itemsSig = (folder.items ?? [])
                    .map { "\($0.cardID)|\($0.variantKey)" }
                    .sorted()
                    .joined(separator: "§")
                return "\(folder.id.uuidString)|\(itemsSig)"
            }
            .joined(separator: "|")
    }

    var body: some View {
        Group {
            if folders.isEmpty {
                ContentUnavailableView(
                    "No Folders",
                    systemImage: "folder",
                    description: Text("Tap + to create your first folder.")
                )
                .frame(minHeight: 280)
            } else {
                List {
                    ForEach(folders) { folder in
                        NavigationLink(value: folder) {
                            folderCard(folder)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Edit Folder", isPresented: Binding(
            get: { folderToEdit != nil },
            set: { if !$0 { folderToEdit = nil } }
        )) {
            TextField("Folder Name", text: $editedFolderTitle)
            Button("Save") {
                guard let folder = folderToEdit else { return }
                let trimmed = editedFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    folder.title = trimmed
                    try? modelContext.save()
                }
                folderToEdit = nil
            }
            Button("Cancel", role: .cancel) {
                folderToEdit = nil
            }
        }
        .task(id: folderValueSignature) {
            await resolveFolderValues()
        }
    }

    private func folderCard(_ folder: CardFolder) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(folderSubtitle(folder))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                modelContext.delete(folder)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                editedFolderTitle = folder.title
                folderToEdit = folder
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func folderSubtitle(_ folder: CardFolder) -> String {
        let count = (folder.items ?? []).count
        let cardsPart = "\(count) \(count == 1 ? "card" : "cards")"
        guard let value = folderValueByID[folder.id] else { return cardsPart }
        return "\(cardsPart) · \(formatGBP(value))"
    }

    private func formatGBP(_ value: Double) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(2)))
    }

    private func resolveFolderValues() async {
        var nextValues: [UUID: Double] = [:]
        var cachedCards: [String: Card] = [:]

        for folder in folders {
            var folderTotal = 0.0
            for item in folder.items ?? [] {
                if cachedCards[item.cardID] == nil {
                    cachedCards[item.cardID] = await services.cardData.loadCard(masterCardId: item.cardID)
                }
                guard let card = cachedCards[item.cardID] else { continue }
                if let usd = await services.pricing.usdPriceForVariant(for: card, variantKey: item.variantKey) {
                    folderTotal += usd * services.pricing.usdToGbp
                }
            }
            nextValues[folder.id] = folderTotal
        }

        folderValueByID = nextValues
    }
}
