import SwiftUI

struct FriendSearchView: View {
    @Environment(AppServices.self) private var services

    @State private var query = ""
    @State private var results: [SocialFriendService.FriendSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                Section {
                    ContentUnavailableView(
                        "Search by Username",
                        systemImage: "magnifyingglass",
                        description: Text("Type at least 2 characters to find other collectors.")
                    )
                    .frame(maxWidth: .infinity)
                }
            } else if isSearching {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } else if results.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "person.2.slash",
                        description: Text("Try a different username.")
                    )
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section("Results") {
                    ForEach(results) { result in
                        NavigationLink {
                            FriendProfileView(username: result.profile.username)
                        } label: {
                            HStack(spacing: 12) {
                                avatar(urlString: result.profile.avatarURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.profile.displayName ?? result.profile.username)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("@\(result.profile.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            relationshipAction(for: result)
                        }
                    }
                        .buttonStyle(.plain)
                    }
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
        .listStyle(.insetGrouped)
        .navigationTitle("Find Friends")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search username"
        )
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func relationshipAction(for result: SocialFriendService.FriendSearchResult) -> some View {
        Group {
            switch result.relationship {
            case .none:
                Button("Add") {
                    Task { await addFriend(for: result.profile.id) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
            case .friends:
                Label("Friends", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            case .pendingOutgoing:
                Label("Pending", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .pendingIncoming(let friendshipID):
                Button("Accept") {
                    Task { await respond(friendshipID: friendshipID, accepted: true) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
            case .blocked:
                Label("Blocked", systemImage: "hand.raised.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    private func avatar(urlString: String?) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 42, height: 42)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Color.secondary.opacity(0.18))
                }
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        defer { isSearching = false }
        do {
            results = try await services.socialFriend.searchUsers(query: trimmed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    private func addFriend(for userID: UUID) async {
        Haptics.mediumImpact()
        do {
            try await services.socialFriend.sendRequest(to: userID)
            Haptics.success()
            await runSearch()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func respond(friendshipID: UUID, accepted: Bool) async {
        Haptics.mediumImpact()
        do {
            try await services.socialFriend.respond(to: friendshipID, accepted: accepted)
            // Accepting a friend feels like a positive completion; declining
            // is more of a neutral dismissal — match the haptic to the user's
            // emotional read of the action.
            if accepted {
                Haptics.success()
            }
            await runSearch()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }
}
