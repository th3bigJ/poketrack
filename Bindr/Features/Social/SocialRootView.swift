import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct SocialRootView: View {

    private enum SocialTab: String, CaseIterable, Identifiable {
        case feed = "Feed"
        case friends = "Friends"
        case profile = "Profile"

        var id: String { rawValue }
        var title: String { rawValue }
    }

    private enum SocialDeepLinkDestination {
        case feed
        case friends
        case friendRequests
        case profile(username: String)
        case content(id: UUID)
        case comment(id: UUID)
        case wishlistMatch(id: UUID)

        static func parse(from url: URL) -> SocialDeepLinkDestination? {
            guard url.scheme?.lowercased() == "bindr" else { return nil }
            let host = url.host?.lowercased() ?? ""
            var normalizedHost = host
            var pathComponents = url.path
                .split(separator: "/")
                .map { $0.lowercased() }
            let hasInlineHost = pathComponents.first == "social" || pathComponents.first == "profile"

            if host.isEmpty, hasInlineHost {
                let first = pathComponents.removeFirst()
                if first == "profile" {
                    guard let rawUsername = pathComponents.first else { return nil }
                    guard rawUsername.hasPrefix("@") else { return nil }
                    let username = String(rawUsername.dropFirst())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    guard !username.isEmpty else { return nil }
                    return .profile(username: username)
                }
                normalizedHost = String(first)
            }

            if host == "profile" {
                let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard rawPath.hasPrefix("@") else { return nil }
                let username = String(rawPath.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !username.isEmpty else { return nil }
                return .profile(username: username)
            }

            guard normalizedHost == "social" else { return nil }

            guard let first = pathComponents.first else { return nil }
            switch first {
            case "feed":
                if let contentID = queryUUID(in: url, keys: ["content_id", "contentid"]) {
                    return .content(id: contentID)
                }
                if let commentID = queryUUID(in: url, keys: ["comment_id", "commentid"]) {
                    return .comment(id: commentID)
                }
                if let wishlistMatchID = queryUUID(in: url, keys: ["wishlist_match_id", "wishlistmatchid"]) {
                    return .wishlistMatch(id: wishlistMatchID)
                }
                guard pathComponents.count >= 2 else { return .feed }
                let deepLinkType = pathComponents[1]
                guard pathComponents.count >= 3 else { return .feed }
                guard let id = UUID(uuidString: pathComponents[2]) else { return .feed }
                switch deepLinkType {
                case "content":
                    return .content(id: id)
                case "comment":
                    return .comment(id: id)
                case "wishlist-match":
                    return .wishlistMatch(id: id)
                default:
                    return .feed
                }
            case "friends":
                if pathComponents.count >= 2, pathComponents[1] == "requests" {
                    return .friendRequests
                }
                return .friends
            default:
                return .feed
            }
        }

        private static func queryUUID(in url: URL, keys: [String]) -> UUID? {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            for item in components.queryItems ?? [] {
                let name = item.name.lowercased()
                guard keys.contains(name) else { continue }
                guard let value = item.value, let uuid = UUID(uuidString: value) else { continue }
                return uuid
            }
            return nil
        }
    }

    @Environment(AppServices.self) private var services

    @State private var profile: SocialProfile?
    @State private var isProfileLoading = false
    @State private var errorMessage: String?
    @State private var showAccountProfile = false
    @State private var profilePopoverPath = NavigationPath()
    @State private var socialNavigationPath = NavigationPath()
    @State private var currentNonce: String?
    @State private var selectedTab: SocialTab = .feed
    @State private var isAlertsPresented = false
    @State private var isNewPostPresented = false
    @State private var deepLinkedSharedContent: SharedContent?
    @State private var deepLinkedCommentsContent: SocialFeedService.FeedContentSummary?

    private var isConfigured: Bool {
        AppConfiguration.supabaseURL != nil && !AppConfiguration.supabasePublishableKey.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            socialHeader
            content
        }
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAccountProfile) {
            profilePopover
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $deepLinkedSharedContent) { content in
            NavigationStack {
                SharedContentView(content: content)
                    .environment(services)
            }
        }
        .sheet(item: $deepLinkedCommentsContent) { content in
            NavigationStack {
                CommentsView(content: content)
                    .environment(services)
            }
        }
        .task {
            await services.socialAuth.restoreSession()
            await refreshProfileIfNeeded()
            await routeQueuedDeepLinkIfPossible()
            await services.socialPush.updateRegistrationState()
        }
        .onChange(of: services.socialAuth.authState) { _, state in
            Task {
                await refreshProfileIfNeeded()
                await routeQueuedDeepLinkIfPossible()
                await services.socialPush.updateRegistrationState()
            }
            if state == .signedOut {
                profilePopoverPath = NavigationPath()
                socialNavigationPath = NavigationPath()
                showAccountProfile = false
            }
        }
        .onChange(of: services.socialPush.queuedDeepLinkURL) { _, _ in
            Task {
                await routeQueuedDeepLinkIfPossible()
            }
        }
    }

    private var socialHeader: some View {
        VStack(spacing: 0) {
            ZStack {
            Text("Social")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                if services.socialAuth.isSignedIn {
                    ChromeGlassCircleButton(accessibilityLabel: "Alerts") {
                        Haptics.lightImpact()
                        isAlertsPresented = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(services.socialFeed.unreadCount > 0 ? Color(hex: "E8B84B") : .primary)

                            if services.socialFeed.unreadCount > 0 {
                                Circle()
                                    .fill(Color(hex: "E05252"))
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                if services.socialAuth.isSignedIn {
                    if selectedTab == .feed {
                        ChromeGlassCircleButton(accessibilityLabel: "New Post") {
                            Haptics.lightImpact()
                            isNewPostPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    } else if selectedTab == .profile {
                        ChromeGlassCircleButton(accessibilityLabel: "Edit Profile") {
                            Haptics.lightImpact()
                            profilePopoverPath.append(AccountProfileView.Destination.editProfile)
                            showAccountProfile = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    ChromeGlassCircleButton(accessibilityLabel: "Profile") {
                        Haptics.lightImpact()
                        showAccountProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
            
            Divider().opacity(0.1)
        }
        .sheet(isPresented: $isAlertsPresented) {
            SocialAlertsSheet(isPresented: $isAlertsPresented) { deepLinkURL in
                services.socialPush.queueDeepLink(url: deepLinkURL)
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isNewPostPresented) {
            SocialShareSheet(item: .card)
                .environment(services)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !isConfigured {
            ContentUnavailableView(
                "Social Not Configured",
                systemImage: "exclamationmark.triangle",
                description: Text("Add `BINDR_SUPABASE_URL` and `BINDR_SUPABASE_PUBLISHABLE_KEY` in `Info.plist` to enable account creation.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if services.socialAuth.isBusy || isProfileLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(services.socialAuth.statusMessage ?? "Loading social…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch services.socialAuth.authState {
            case .signedOut:
                signInCard
            case .signedIn:
                signedInContent
            }
        }
    }

    private var signInCard: some View {
        Form {
            Section {
                Text("Sign in with your Apple ID to create and sync your social profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SignInWithAppleButton(.signIn) { request in
                    let nonce = randomNonceString()
                    currentNonce = nonce
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = sha256(nonce)
                } onCompletion: { result in
                    Task {
                        await handleAppleSignInResult(result)
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
            } header: {
                Text("Account")
            } footer: {
                Text("This uses Apple’s native authentication sheet and then exchanges the Apple identity token for a Supabase session.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var signedInContent: some View {
        if let profile {
            NavigationStack(path: $socialNavigationPath) {
                VStack(spacing: 0) {
                    socialShell(profile: profile)
                }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SocialDestination.self) { destination in
                    switch destination {
                    case .friends:
                        FriendsListView(
                            onOpenSearch: { socialNavigationPath.append(SocialDestination.search) },
                            onOpenQR: { socialNavigationPath.append(SocialDestination.qrProfile) },
                            onOpenUsername: { username in
                                socialNavigationPath.append(SocialDestination.friendProfile(username: username))
                            }
                        )
                    case .search:
                        FriendSearchView()
                    case .qrProfile:
                        QRProfileView(username: profile.username) { scannedUsername in
                            socialNavigationPath.append(SocialDestination.friendProfile(username: scannedUsername))
                        }
                    case .friendProfile(let username):
                        FriendProfileView(username: username)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Create Your Profile",
                systemImage: "person.crop.circle.badge.plus",
                description: Text("Create your social profile first, then you can send and accept friend requests.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func socialShell(profile: SocialProfile) -> some View {
        VStack(spacing: 0) {
            SlidingSegmentedPicker(
                selection: $selectedTab,
                items: SocialTab.allCases,
                title: { $0.title }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Group {
                switch selectedTab {
                case .feed:
                    FeedView()
                case .friends:
                    FriendsListView(
                        onOpenSearch: { selectedTab = .friends },
                        onOpenQR: { socialNavigationPath.append(SocialDestination.qrProfile) },
                        onOpenUsername: { username in
                            socialNavigationPath.append(SocialDestination.friendProfile(username: username))
                        }
                    )
                case .profile:
                    MyProfileView(
                        profile: profile,
                        onSignOutTapped: {
                            services.socialAuth.signOut()
                            self.profile = nil
                            selectedTab = .feed
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Sign in with Apple returned an unexpected credential type."
                return
            }
            guard
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Unable to read Apple identity token."
                return
            }

            try await services.socialAuth.signInWithApple(
                idToken: idToken,
                rawNonce: currentNonce,
                appleUserIdentifier: credential.user
            )
            await refreshProfileIfNeeded()
            await MainActor.run {
                profilePopoverPath = NavigationPath()
                if profile == nil {
                    profilePopoverPath.append(AccountProfileView.Destination.editProfile)
                }
                showAccountProfile = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce.")
            }

            randomBytes.forEach { byte in
                if remainingLength == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func refreshProfileIfNeeded() async {
        switch services.socialAuth.authState {
        case .signedOut:
            profile = nil
            return
        case .signedIn:
            break
        }

        isProfileLoading = true
        defer { isProfileLoading = false }
        do {
            profile = try await services.socialProfile.fetchMyProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func routeQueuedDeepLinkIfPossible() async {
        guard case .signedIn = services.socialAuth.authState else { return }
        if let url = services.socialPush.consumeQueuedDeepLinkURL(),
           let destination = SocialDeepLinkDestination.parse(from: url) {
            await route(destination: destination)
            return
        }

        guard let username = services.socialFriend.consumeQueuedProfileUsername() else { return }
        await route(destination: .profile(username: username))
    }

    private func route(destination: SocialDeepLinkDestination) async {
        switch destination {
        case .feed:
            selectedTab = .feed
        case .friends, .friendRequests:
            selectedTab = .friends
        case .profile(let username):
            if profile == nil {
                profilePopoverPath = NavigationPath()
                profilePopoverPath.append(AccountProfileView.Destination.editProfile)
                showAccountProfile = true
            } else {
                selectedTab = .friends
                socialNavigationPath = NavigationPath()
                socialNavigationPath.append(SocialDestination.friendProfile(username: username))
            }
        case .content(let id):
            selectedTab = .feed
            guard let sharedContent = try? await services.socialShare.fetchSharedContent(id: id) else { return }
            deepLinkedCommentsContent = nil
            deepLinkedSharedContent = sharedContent
        case .comment(let id):
            selectedTab = .feed
            if let sharedContent = try? await services.socialShare.fetchSharedContent(id: id) {
                deepLinkedSharedContent = nil
                deepLinkedCommentsContent = feedContentSummary(from: sharedContent)
                return
            }
            guard let contentID = try? await services.socialFeed.fetchContentID(forCommentID: id) else { return }
            guard let sharedContent = try? await services.socialShare.fetchSharedContent(id: contentID) else { return }
            deepLinkedSharedContent = nil
            deepLinkedCommentsContent = feedContentSummary(from: sharedContent)
        case .wishlistMatch(let id):
            selectedTab = .feed
            if let sharedContent = try? await services.socialShare.fetchSharedContent(id: id) {
                deepLinkedCommentsContent = nil
                deepLinkedSharedContent = sharedContent
                return
            }
            guard let contentID = try? await services.socialFeed.fetchContentID(forWishlistMatchID: id) else { return }
            guard let sharedContent = try? await services.socialShare.fetchSharedContent(id: contentID) else { return }
            deepLinkedCommentsContent = nil
            deepLinkedSharedContent = sharedContent
        }
    }

    private func feedContentSummary(from sharedContent: SharedContent) -> SocialFeedService.FeedContentSummary {
        SocialFeedService.FeedContentSummary(
            id: sharedContent.id,
            ownerID: sharedContent.ownerID,
            title: sharedContent.title,
            contentType: sharedContent.contentType,
            description: sharedContent.description,
            cardCount: sharedContent.cardCount,
            brand: sharedContent.brand
        )
    }

    private var profilePopover: some View {
        NavigationStack(path: $profilePopoverPath) {
            AccountProfileView(
                navigationPath: $profilePopoverPath,
                isPresented: $showAccountProfile,
                externalProfile: $profile
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        showAccountProfile = false
                    }
                    .foregroundStyle(.primary)
                    .fontWeight(.bold)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
