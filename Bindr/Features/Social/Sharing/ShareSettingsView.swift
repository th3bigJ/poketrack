import SwiftUI

enum ShareSettingsSource {
    case binder(Binder)
    case deck(Deck)
    case wishlist(items: [WishlistItem])
    case collection(items: [CollectionItem])
}

struct ShareSettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    let source: ShareSettingsSource
    let onDidChange: (() -> Void)?

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var visibility: SharedContentVisibility = .friends
    @State private var includeValue = false
    @State private var isPublished = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showPaywall = false

    init(source: ShareSettingsSource, onDidChange: (() -> Void)? = nil) {
        self.source = source
        self.onDidChange = onDidChange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    Picker("Visibility", selection: $visibility) {
                        Text("Friends").tag(SharedContentVisibility.friends)
                        Text("Link").tag(SharedContentVisibility.link)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Include market value", isOn: $includeValue)
                } header: {
                    Text("Publication")
                } footer: {
                    Text("By default, only card identity data is published. Turning on market value adds current market estimates only.")
                }

                Section {
                    if isPublished {
                        Button(role: .destructive) {
                            Task { await unpublish() }
                        } label: {
                            if isBusy {
                                ProgressView()
                            } else {
                                Text("Unpublish")
                            }
                        }
                        .disabled(isBusy)
                    } else {
                        Button {
                            Task { await publish() }
                        } label: {
                            if isBusy {
                                ProgressView()
                            } else {
                                Text("Publish")
                            }
                        }
                        .disabled(isBusy)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Share Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadSnapshot()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallSheet()
                    .environment(services)
            }
        }
    }

    private func loadSnapshot() async {
        do {
            let snapshot: SocialShareService.ShareSnapshot
            switch source {
            case .binder(let binder):
                snapshot = try await services.socialShare.shareSnapshot(for: binder)
            case .deck(let deck):
                snapshot = try await services.socialShare.shareSnapshot(for: deck)
            case .wishlist:
                snapshot = try await services.socialShare.shareSnapshotForWishlist()
            case .collection:
                snapshot = try await services.socialShare.shareSnapshotForCollection()
            }
            title = snapshot.title
            descriptionText = snapshot.description
            visibility = snapshot.visibility
            includeValue = snapshot.includeValue
            isPublished = snapshot.isPublished
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publish() async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch source {
            case .binder(let binder):
                _ = try await services.socialShare.publishBinder(
                    binder,
                    title: title,
                    description: descriptionText,
                    visibility: visibility,
                    includeValue: includeValue
                )
            case .deck(let deck):
                _ = try await services.socialShare.publishDeck(
                    deck,
                    title: title,
                    description: descriptionText,
                    visibility: visibility,
                    includeValue: includeValue
                )
            case .wishlist(let items):
                _ = try await services.socialShare.publishWishlist(
                    title: title,
                    description: descriptionText,
                    visibility: visibility,
                    includeValue: includeValue,
                    wishlistItems: items
                )
            case .collection(let items):
                _ = try await services.socialShare.publishCollection(
                    title: title,
                    description: descriptionText,
                    visibility: visibility,
                    includeValue: includeValue,
                    collectionItems: items
                )
            }
            isPublished = true
            errorMessage = nil
            onDidChange?()
        } catch {
            if case SocialShareService.SocialShareError.freeTierLimitReached = error {
                showPaywall = true
            } else if case SocialShareService.SocialShareError.deckSharingRequiresPremium = error {
                showPaywall = true
            }
            errorMessage = error.localizedDescription
        }
    }

    private func unpublish() async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch source {
            case .binder(let binder):
                try await services.socialShare.unpublishBinder(binder)
            case .deck(let deck):
                try await services.socialShare.unpublishDeck(deck)
            case .wishlist:
                try await services.socialShare.unpublishWishlist()
            case .collection:
                try await services.socialShare.unpublishCollection()
            }
            isPublished = false
            errorMessage = nil
            onDidChange?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
