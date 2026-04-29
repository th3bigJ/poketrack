import SwiftUI

struct FriendsListView: View {
    private enum FriendsTab: String, CaseIterable {
        case mine = "My Friends"
        case find = "Find Trainers"
    }

    @Environment(AppServices.self) private var services

    let onOpenSearch: () -> Void
    let onOpenQR: () -> Void
    let onOpenUsername: (String) -> Void

    @State private var selectedTab: FriendsTab = .mine
    @State private var friends: [SocialProfile] = []
    @State private var incomingRequests: [SocialFriendService.IncomingFriendRequest] = []
    @State private var outgoingRequests: [SocialFriendService.OutgoingFriendRequest] = []
    @State private var searchText = ""
    @State private var searchResults: [SocialFriendService.FriendSearchResult] = []
    @State private var isLoading = false
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker

            if selectedTab == .find {
                searchField
                    .padding(.top, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if selectedTab == .mine {
                        myFriendsContent
                    } else {
                        findTrainersContent
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "E05252"))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "E05252").opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .refreshable { await refresh() }
        }
        .background(Color(uiColor: .systemBackground))
        .task { await refresh() }
        .onChange(of: searchText) { _, newValue in
            Task { await search(query: newValue) }
        }
    }

    private var header: some View {
        HStack {
            Text("Friends")
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.primary)
            Spacer()
            Button(action: onOpenQR) {
                Image(systemName: "qrcode")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: "E8B84B"))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.09), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(FriendsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    if tab == .find {
                        onOpenSearch()
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? Color.black : Color.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color(hex: "E8B84B") : Color(uiColor: .secondarySystemBackground), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(selectedTab == tab ? .clear : Color.primary.opacity(0.09), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.3))
            TextField("Search trainers...", text: $searchText)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary)
                .tint(Color(hex: "E8B84B"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var myFriendsContent: some View {
        if isLoading {
            loadingCard("Loading friends...")
        }

        if !incomingRequests.isEmpty {
            sectionLabel("PENDING REQUESTS · \(incomingRequests.count)")
            ForEach(incomingRequests) { request in
                pendingRequestCard(request)
            }
        }

        sectionLabel("FOLLOWING · \(friends.count)")
        if friends.isEmpty && !isLoading {
            emptyCard("No friends yet. Find trainers by username or scan a QR code.")
        } else {
            ForEach(friends) { friend in
                profileRow(profile: friend, detail: profileStats(friend), buttonTitle: "Following") {
                    onOpenUsername(friend.username)
                }
            }
        }

        if !outgoingRequests.isEmpty {
            sectionLabel("SENT REQUESTS · \(outgoingRequests.count)")
            ForEach(outgoingRequests) { request in
                profileRow(profile: request.addressee, detail: "Request pending", buttonTitle: "Pending") {
                    onOpenUsername(request.addressee.username)
                }
            }
        }
    }

    @ViewBuilder
    private var findTrainersContent: some View {
        if isSearching {
            loadingCard("Searching trainers...")
        }

        let rows = searchResults
        if rows.isEmpty && !isSearching {
            emptyCard(searchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ? "Type at least two characters to search trainers." : "No trainers found.")
        } else {
            ForEach(rows) { result in
                searchResultRow(result)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.88)
            .foregroundStyle(Color.secondary.opacity(0.5))
    }

    private func pendingRequestCard(_ request: SocialFriendService.IncomingFriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProfileAvatarView(profile: request.requester, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.requester.displayName ?? request.requester.username)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text("@\(request.requester.username) wants to follow you")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Accept") {
                    Task { await respond(to: request.friendship.id, accepted: true) }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(hex: "E8B84B"), in: Capsule())

                Button {
                    Task { await respond(to: request.friendship.id, accepted: false) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 36, height: 32)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                        .overlay(Capsule().stroke(Color.primary.opacity(0.09), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(hex: "5B9CF6").opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "5B9CF6").opacity(0.19), lineWidth: 1)
        }
    }

    private func profileRow(profile: SocialProfile, detail: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProfileAvatarView(profile: profile, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName ?? profile.username)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text("@\(profile.username)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                }
                Spacer()
                Text(buttonTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(buttonTitle == "Following" || buttonTitle == "Pending" ? Color.secondary : Color(hex: "E8B84B"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func searchResultRow(_ result: SocialFriendService.FriendSearchResult) -> some View {
        profileRow(profile: result.profile, detail: profileStats(result.profile), buttonTitle: relationshipButtonTitle(result.relationship)) {
            Task { await handleSearchResultTap(result) }
        }
    }

    private func loadingCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color(hex: "E8B84B"))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
    }

    private func profileStats(_ profile: SocialProfile) -> String {
        let cards = profile.collectionCardCount ?? 0
        let decks = profile.collectionDeckCount ?? 0
        let friends = profile.friendCount ?? 0
        return "\(cards) cards · \(decks) decks · \(friends) friends"
    }

    private func relationshipButtonTitle(_ state: SocialFriendService.RelationshipState) -> String {
        switch state {
        case .none: return "Follow"
        case .pendingIncoming: return "Accept"
        case .pendingOutgoing: return "Pending"
        case .friends: return "Following"
        case .blocked: return "Blocked"
        }
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

    private func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await services.socialFriend.searchUsers(query: trimmed)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respond(to friendshipID: UUID, accepted: Bool) async {
        Haptics.mediumImpact()
        do {
            try await services.socialFriend.respond(to: friendshipID, accepted: accepted)
            if accepted { Haptics.success() }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func handleSearchResultTap(_ result: SocialFriendService.FriendSearchResult) async {
        switch result.relationship {
        case .none:
            Haptics.mediumImpact()
            do {
                try await services.socialFriend.sendRequest(to: result.profile.id)
                Haptics.success()
                await search(query: searchText)
            } catch {
                errorMessage = error.localizedDescription
                Haptics.error()
            }
        case .pendingIncoming(let friendshipID):
            await respond(to: friendshipID, accepted: true)
            await search(query: searchText)
        default:
            Haptics.lightImpact()
            onOpenUsername(result.profile.username)
        }
    }
}
