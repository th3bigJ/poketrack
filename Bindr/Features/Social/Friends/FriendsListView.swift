import SwiftUI

struct FriendsListView: View {
    @Environment(AppServices.self) private var services

    let onOpenSearch: () -> Void
    let onOpenQR: () -> Void
    let onOpenUsername: (String) -> Void

    @State private var friends: [SocialProfile] = []
    @State private var incomingRequests: [SocialFriendService.IncomingFriendRequest] = []
    @State private var outgoingRequests: [SocialFriendService.OutgoingFriendRequest] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    quickGlassButton(
                        icon: "magnifyingglass",
                        title: "Find",
                        action: onOpenSearch
                    )
                    quickGlassButton(
                        icon: "qrcode",
                        title: "QR",
                        action: onOpenQR
                    )
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            if isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading friends…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !incomingRequests.isEmpty {
                Section("Pending Requests") {
                    ForEach(incomingRequests) { request in
                        NavigationLink {
                            FriendRequestView(request: request) {
                                Task { await refresh() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                avatar(urlString: request.requester.avatarURL)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(request.requester.displayName ?? request.requester.username)
                                        .font(.body.weight(.semibold))
                                    Text("@\(request.requester.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !outgoingRequests.isEmpty {
                Section("Sent Requests") {
                    ForEach(outgoingRequests) { request in
                        HStack(spacing: 12) {
                            avatar(urlString: request.addressee.avatarURL)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(request.addressee.displayName ?? request.addressee.username)
                                    .font(.body.weight(.semibold))
                                Text("@\(request.addressee.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("Pending", systemImage: "clock")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Friends (\(friends.count))") {
                if friends.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Friends Yet",
                        systemImage: "person.2.slash",
                        description: Text("Find collectors by username or scan their QR.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(friends) { friend in
                        Button {
                            onOpenUsername(friend.username)
                        } label: {
                            HStack(spacing: 12) {
                                avatar(urlString: friend.avatarURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.displayName ?? friend.username)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("@\(friend.username)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
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
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
        }
    }

    private func quickGlassButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if #available(iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func avatar(urlString: String?) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 44, height: 44)) { image in
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
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let friendsTask = services.socialFriend.fetchFriends()
            async let incomingTask = services.socialFriend.fetchPendingRequests()
            async let outgoingTask = services.socialFriend.fetchOutgoingPendingRequests()
            friends = try await friendsTask
            incomingRequests = try await incomingTask
            outgoingRequests = try await outgoingTask
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
