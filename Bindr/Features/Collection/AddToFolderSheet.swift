import SwiftUI
import SwiftData

struct AddToFolderSheetPayload: Identifiable {
    let id = UUID()
    let card: Card
    let variantKey: String
}

struct AddToFolderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let card: Card
    let variantKey: String

    @Query(sort: \CardFolder.createdAt, order: .reverse) private var folders: [CardFolder]

    @State private var showCreateAlert = false
    @State private var newFolderTitle = ""
    @State private var addedFolderIDs: Set<UUID> = []

    private var headerButtonColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newFolderTitle = ""
                        showCreateAlert = true
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                            .foregroundStyle(.primary)
                    }
                }

                if !folders.isEmpty {
                    Section("MY FOLDERS") {
                        ForEach(folders) { folder in
                            let alreadyAdded = addedFolderIDs.contains(folder.id) || folderContainsCard(folder)
                            Button {
                                guard !alreadyAdded else { return }
                                addCard(to: folder)
                            } label: {
                                HStack {
                                    Label(folder.title, systemImage: "folder")
                                        .foregroundStyle(alreadyAdded ? .secondary : .primary)
                                    Spacer()
                                    if alreadyAdded {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("\((folder.items ?? []).count) cards")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(headerButtonColor)
                }
            }
            .alert("New Folder", isPresented: $showCreateAlert) {
                TextField("Folder name", text: $newFolderTitle)
                Button("Create") { createAndAdd() }
                Button("Cancel", role: .cancel) { newFolderTitle = "" }
            }
        }
        .tint(headerButtonColor)
    }

    private func folderContainsCard(_ folder: CardFolder) -> Bool {
        (folder.items ?? []).contains { $0.cardID == card.masterCardId && $0.variantKey == variantKey }
    }

    private func addCard(to folder: CardFolder) {
        let item = CardFolderItem(cardID: card.masterCardId, variantKey: variantKey)
        item.folder = folder
        modelContext.insert(item)
        try? modelContext.save()
        addedFolderIDs.insert(folder.id)
    }

    private func createAndAdd() {
        let title = newFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let folder = CardFolder(title: title)
        modelContext.insert(folder)
        let item = CardFolderItem(cardID: card.masterCardId, variantKey: variantKey)
        item.folder = folder
        modelContext.insert(item)
        try? modelContext.save()
        addedFolderIDs.insert(folder.id)
        newFolderTitle = ""
    }
}
