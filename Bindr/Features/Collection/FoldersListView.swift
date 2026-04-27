import SwiftUI
import SwiftData

struct FoldersListView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]
    @State private var folderValueByID: [UUID: Double] = [:]

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
        ScrollView {
            VStack(spacing: 0) {
                if folders.isEmpty {
                    ContentUnavailableView(
                        "No Folders",
                        systemImage: "folder",
                        description: Text("Tap + to create your first folder.")
                    )
                    .frame(minHeight: 280)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(folders) { folder in
                            NavigationLink(value: folder) {
                                folderCard(folder)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelContext.delete(folder)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
