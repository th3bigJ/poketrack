import SwiftUI

struct FriendProfileView: View {
    @Environment(AppServices.self) private var services

    let username: String

    @State private var profile: SocialProfile?
    @State private var relationship: SocialFriendService.RelationshipState = .none
    @State private var sharedContent: [SharedContent] = []
    @State private var isLoading = false
    @State private var isLoadingSharedContent = false
    @State private var isMutating = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let profile {
                ScrollView {
                    VStack(spacing: 20) {
                        heroCard(profile: profile)
                        relationshipCard(for: profile)
                        sharedContentCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            } else {
                ContentUnavailableView(
                    "Profile Not Found",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("This username does not exist or is no longer available.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("@\(username)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Actions", systemImage: "ellipsis.circle") {
                    if let profile {
                        Button("Block User", role: .destructive) {
                            Task { await block(profile.id) }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await refresh()
        }
    }

    private func heroCard(profile: SocialProfile) -> some View {
        VStack(spacing: 12) {
            avatar(urlString: profile.avatarURL)
            VStack(spacing: 3) {
                Text(profile.displayName ?? profile.username)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(glassCardBackground)
    }

    private func relationshipCard(for profile: SocialProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friend Status")
                .font(.headline)

            HStack(spacing: 12) {
                Text(relationshipLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                actionButton(for: profile.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(glassCardBackground)
    }

    @ViewBuilder
    private var sharedContentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shared Content")
                    .font(.headline)
                Spacer()
                if isLoadingSharedContent {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if sharedContent.isEmpty {
                Text("No published binders, decks, or wishlist snapshots yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sharedContent) { entry in
                    NavigationLink {
                        SharedContentView(content: entry)
                            .environment(services)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(entry.contentType.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.visibility == .link {
                                Label("Link", systemImage: "link")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    if entry.id != sharedContent.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(glassCardBackground)
    }

    @ViewBuilder
    private func actionButton(for userID: UUID) -> some View {
        switch relationship {
        case .none:
            Button("Add Friend") {
                Task { await sendRequest(to: userID) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMutating)
        case .friends:
            Label("Friends", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        case .pendingOutgoing:
            Label("Pending", systemImage: "clock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .pendingIncoming(let friendshipID):
            Button("Accept") {
                Task { await respond(to: friendshipID, accepted: true) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMutating)
        case .blocked:
            Label("Blocked", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
        }
    }

    private func avatar(urlString: String?) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 72, height: 72)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
        .frame(width: 72, height: 72)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var glassCardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }

    private var relationshipLabel: String {
        switch relationship {
        case .none:
            return "Not connected"
        case .pendingIncoming:
            return "Requested you"
        case .pendingOutgoing:
            return "Request sent"
        case .friends:
            return "Friends"
        case .blocked:
            return "Blocked"
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await services.socialFriend.fetchProfile(username: username)
            profile = loaded
            if let loaded {
                relationship = try await services.socialFriend.fetchRelationshipState(for: loaded.id)
                await refreshSharedContent(ownerID: loaded.id)
            } else {
                relationship = .none
                sharedContent = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sendRequest(to userID: UUID) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.sendRequest(to: userID)
            relationship = try await services.socialFriend.fetchRelationshipState(for: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respond(to friendshipID: UUID, accepted: Bool) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.respond(to: friendshipID, accepted: accepted)
            relationship = accepted ? .friends : .none
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func block(_ userID: UUID) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await services.socialFriend.block(userID: userID)
            relationship = .blocked
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSharedContent(ownerID: UUID) async {
        isLoadingSharedContent = true
        defer { isLoadingSharedContent = false }
        do {
            sharedContent = try await services.socialShare.fetchSharedContent(ownerID: ownerID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
