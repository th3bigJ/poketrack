import SwiftUI
import SwiftData

struct FoldersListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]

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
                Text("\((folder.items ?? []).count) \((folder.items ?? []).count == 1 ? "card" : "cards")")
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
}
