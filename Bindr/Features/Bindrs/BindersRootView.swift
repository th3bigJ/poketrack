import SwiftUI
import SwiftData

struct BindersRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Query(sort: \Binder.createdAt, order: .reverse) private var binders: [Binder]

    @Binding var showCreateSheet: Bool
    @State private var showPaywall = false
    @State private var binderToDelete: Binder?
    @State private var presentedBinder: Binder?
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            if binders.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        Color.clear.frame(height: rootFloatingChromeInset)
                        ContentUnavailableView {
                            Label("No Binders", systemImage: "books.vertical")
                        } description: {
                            Text("Create a binder to organise your cards.")
                        } actions: {
                            Button("Create a Binder") { handleCreateTap() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: rootFloatingChromeInset)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(binders) { binder in
                                Button {
                                    presentedBinder = binder
                                } label: {
                                    BinderCardCell(binder: binder)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        binderToDelete = binder
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete Binder", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $presentedBinder) { binder in
            BinderDetailView(binder: binder)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateBinderSheet()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
                .environment(services)
        }
        .confirmationDialog("Delete Binder?", isPresented: $showDeleteConfirm, presenting: binderToDelete) { binder in
            Button("Delete \"\(binder.title)\"", role: .destructive) {
                modelContext.delete(binder)
            }
            Button("Cancel", role: .cancel) {}
        } message: { binder in
            Text("This will permanently remove \"\(binder.title)\" and all its slots.")
        }
    }

    private func handleCreateTap() {
        if !services.store.isPremium && binders.count >= 1 {
            showPaywall = true
        } else {
            showCreateSheet = true
        }
    }
}

private struct BinderCardCell: View {
    @Environment(AppServices.self) private var services
    let binder: Binder
    @State private var cardURLs: [URL?] = [nil, nil, nil]

    var body: some View {
        BinderCoverView(
            title: binder.title,
            subtitle: "\(binder.slotList.count) cards · \(binder.layout.displayName)",
            colourName: binder.colour,
            texture: binder.textureKind,
            seed: binder.textureSeed,
            peekingCardURLs: cardURLs,
            compact: true
        )
        .task {
            await loadCardURLs()
        }
    }

    private func loadCardURLs() async {
        let slots = binder.slotList.prefix(3)
        var urls: [URL?] = []
        
        for slot in slots {
            if let card = await services.cardData.loadCard(masterCardId: slot.cardID) {
                urls.append(AppConfiguration.imageURL(relativePath: card.imageLowSrc))
            } else {
                urls.append(nil)
            }
        }
        
        while urls.count < 3 { urls.append(nil) }
        cardURLs = urls
    }
}


