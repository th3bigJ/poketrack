import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

enum SocialTab: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case friends = "Friends"
    case trades = "Trade"
    case profile = "Profile"

    static let allCases: [SocialTab] = [.feed, .trades, .friends, .profile]

    var id: String { rawValue }
    var title: String { rawValue }
}

struct SocialRootChromeActionRequest: Equatable {
    enum Action: Equatable {
        case newPost
        case addFriend
        case newTrade
        case editProfile
    }

    let id = UUID()
    let action: Action
}

struct SocialRootView: View {

    private enum SocialDeepLinkDestination {
        case feed
        case friends
        case friendRequests
        case profile(username: String)
        case content(id: UUID)
        case post(id: UUID)
        case comment(id: UUID)
        case wishlistMatch(id: UUID)
        case trade(id: UUID)
        case tradesList

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
                if let postID = queryUUID(in: url, keys: ["post_id", "postid"]) {
                    return .post(id: postID)
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
                case "post":
                    return .post(id: id)
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
            case "trades":
                if pathComponents.count >= 2, let id = UUID(uuidString: String(pathComponents[1])) {
                    return .trade(id: id)
                }
                return .tradesList
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
    @Environment(\.scenePhase) private var scenePhase
    private let externalSelectedTab: Binding<SocialTab>?
    private let isNavigationActive: Binding<Bool>?
    private let chromeActionRequest: Binding<SocialRootChromeActionRequest?>?

    @State private var profile: SocialProfile?
    @State private var isProfileLoading = false
    @State private var errorMessage: String?
    @State private var showAccountProfile = false
    @State private var profilePopoverPath = NavigationPath()
    @State private var socialNavigationPath = NavigationPath()
    @State private var currentNonce: String?
    @State private var localSelectedTab: SocialTab = .feed
    @State private var selectedProfileTab: MyProfileView.ProfileTab = .posts
    @State private var isAlertsPresented = false
    @State private var isNewPostPresented = false
    @State private var isFriendSearchSheetPresented = false
    @State private var isStartTradeSheetPresented = false
    @State private var pendingTradeSheetFriend: SocialProfile?
    @State private var deepLinkedSharedContent: SharedContent?
    @State private var deepLinkedCommentsContent: SocialFeedService.FeedContentSummary?
    @Environment(\.rootFloatingChromeInset) private var rootFloatingChromeInset
    @Environment(\.presentUniversalSearch) private var presentUniversalSearch

    init(
        selectedTab: Binding<SocialTab>? = nil,
        isNavigationActive: Binding<Bool>? = nil,
        chromeActionRequest: Binding<SocialRootChromeActionRequest?>? = nil
    ) {
        self.externalSelectedTab = selectedTab
        self.isNavigationActive = isNavigationActive
        self.chromeActionRequest = chromeActionRequest
    }

    private var selectedTab: SocialTab {
        externalSelectedTab?.wrappedValue ?? localSelectedTab
    }

    private var selectedTabBinding: Binding<SocialTab> {
        Binding {
            selectedTab
        } set: { newValue in
            localSelectedTab = newValue
            externalSelectedTab?.wrappedValue = newValue
        }
    }

    private var isConfigured: Bool {
        AppConfiguration.supabaseURL != nil && !AppConfiguration.supabasePublishableKey.isEmpty
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bindrPageBackground()
        .tint(.primary)
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .tabBar)
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isFriendSearchSheetPresented) {
            NavigationStack {
                FriendSearchView(showsDoneButton: true)
                    .environment(services)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isStartTradeSheetPresented, onDismiss: {
            handleStartTradeSheetDismiss()
        }) {
            NavigationStack {
                FriendsListView(
                    onOpenSearch: {},
                    onOpenQR: { pushSocialDestination(.qrProfile) },
                    onOpenUsername: { username in
                        pushSocialDestination(.friendProfile(username: username))
                    },
                    onSelectFriendForTrade: { friend in
                        pendingTradeSheetFriend = friend
                        isStartTradeSheetPresented = false
                    },
                    standaloneTitle: "Start Trade",
                    standaloneCloseSystemImage: "xmark"
                )
                .environment(services)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .onAppear {
                services.pendingTradeSeed = nil
                services.isCreatingNewTrade = true
            }
        }
        .task {
            await services.socialAuth.restoreSession()
            await refreshProfileIfNeeded()
            await routeQueuedDeepLinkIfPossible()
            await services.socialPush.updateRegistrationState()
            
            // Periodically refresh unread alert counts while Social is active and foregrounded.
            while !Task.isCancelled {
                if scenePhase == .active {
                    await services.socialFeed.refreshUnreadCounts()
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
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
                isNavigationActive?.wrappedValue = false
                showAccountProfile = false
            }
        }
        .onChange(of: services.socialPush.queuedDeepLinkURL) { _, _ in
            Task {
                await routeQueuedDeepLinkIfPossible()
            }
        }
        .onChange(of: socialNavigationPath.count) { _, _ in
            updateNavigationActiveState()
        }
        .onChange(of: chromeActionRequest?.wrappedValue?.id) { _, _ in
            handleChromeActionRequest()
        }
        .onAppear {
            updateNavigationActiveState()
        }
        .onDisappear {
            isNavigationActive?.wrappedValue = false
        }
    }

    private var socialHeader: some View {
        BindrPageHeader(
            title: "Social",
            leading: { socialHeaderLeading },
            trailing: { socialHeaderTrailing }
        )
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
    private var socialHeaderLeading: some View {
        ChromeGlassCircleButton(accessibilityLabel: "Search") {
            Haptics.lightImpact()
            presentUniversalSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var socialAlertsButton: some View {
        ChromeGlassCircleButton(accessibilityLabel: "Alerts") {
            Haptics.lightImpact()
            isAlertsPresented = true
        } label: {
            if services.socialFeed.unreadAlertsCount > 0 {
                Image(systemName: "bell.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BindrPalette.alertRed)
                    .bindrBadge(count: services.socialFeed.unreadAlertsCount)
            } else {
                Image(systemName: "bell")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
    }

    /// Trailing action group. Branches by `selectedTab` but is wrapped in an
    /// animated container so SwiftUI cross-fades the swap rather than tearing
    /// the buttons down and re-creating them — that tear-down was the source
    /// of the visible "flash" when switching tabs.
    @ViewBuilder
    private var socialHeaderTrailing: some View {
        if services.socialAuth.isSignedIn {
            signedInTrailingButtons
        }
    }

    @ViewBuilder
    private var signedInTrailingButtons: some View {
        switch selectedTab {
        case .feed:
            HStack(spacing: 12) {
                ChromeGlassCircleButton(accessibilityLabel: "New Post") {
                    Haptics.lightImpact()
                    presentNewPost()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                }

                socialAlertsButton
            }
        case .trades:
            ChromeGlassCircleButton(accessibilityLabel: "Create trade") {
                Haptics.lightImpact()
                startNewTrade()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
        case .friends:
            if services.pendingTradeSeed != nil || services.isCreatingNewTrade {
                Button("Cancel") {
                    Haptics.lightImpact()
                    services.pendingTradeSeed = nil
                    services.isCreatingNewTrade = false
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background {
                    if #available(iOS 26.0, *) {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.clear.tint(nil).interactive(), in: Capsule())
                    } else {
                        Capsule()
                            .fill(.thinMaterial)
                            .overlay {
                                Capsule()
                                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        case .profile:
            ChromeGlassCircleButton(accessibilityLabel: "Edit Profile") {
                Haptics.lightImpact()
                editProfile()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
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
        SocialLandingView(
            currentNonce: $currentNonce,
            errorMessage: errorMessage,
            headerInset: rootFloatingChromeInset,
            isBusy: services.socialAuth.isBusy,
            onSignInResult: { result in
                Task { await handleAppleSignInResult(result) }
            },
            onGoogleSignIn: {
                Task { await handleGoogleSignIn() }
            }
        )
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
                            onOpenSearch: { pushSocialDestination(.search) },
                            onOpenQR: { pushSocialDestination(.qrProfile) },
                            onOpenUsername: { username in
                                pushSocialDestination(.friendProfile(username: username))
                            },
                            onSelectFriendForTrade: { friend in
                                openSeededTradeBuilder(with: friend)
                            }
                        )
                        .onDisappear {
                            services.pendingTradeSeed = nil
                            services.isCreatingNewTrade = false
                        }
                    case .search:
                        FriendSearchView()
                    case .qrProfile:
                        QRProfileView(username: profile.username) { scannedUsername in
                            pushSocialDestination(.friendProfile(username: scannedUsername))
                        }
                    case .mutualTrade(let sessionID, let otherUserID, let otherUsername):
                        MutualTradeView(
                            navigationPath: $socialNavigationPath,
                            sessionID: sessionID,
                            otherUserID: otherUserID,
                            otherUsername: otherUsername
                        )
                    case .friendProfile(let username):
                        FriendProfileView(username: username, navigationPath: $socialNavigationPath)
                    case .friendCollection(let username):
                        FriendProfileView(username: username, navigationPath: $socialNavigationPath, initialTab: .collection)
                    case .friendsCollection:
                        FriendsCollectionView()
                    case .tradeDetail(let tradeID):
                        TradeDetailView(navigationPath: $socialNavigationPath, tradeID: tradeID)
                    case .tradeBuilder(let receiverID, let theirCards, let myCards, let existingTradeID, let originalTrade, let mySideOnly):
                        TradeBuilderView(
                            receiverID: receiverID,
                            initialTheirCards: theirCards,
                            initialMyCards: myCards,
                            existingTradeID: existingTradeID,
                            originalTrade: originalTrade,
                            mySideOnly: mySideOnly
                        )
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
        return VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .feed:
                    FeedView(selectedTab: selectedTabBinding, headerInset: rootFloatingChromeInset)
                case .friends:
                    FriendsListView(
                        onOpenSearch: {},
                        onOpenQR: { pushSocialDestination(.qrProfile) },
                        onOpenUsername: { username in
                            pushSocialDestination(.friendProfile(username: username))
                        },
                        onSelectFriendForTrade: { friend in
                            openSeededTradeBuilder(with: friend)
                        },
                        socialSelectedTab: selectedTabBinding,
                        headerInset: rootFloatingChromeInset
                    )
                case .trades:
                    TradesView(
                        navigationPath: $socialNavigationPath,
                        selectedTab: selectedTabBinding,
                        headerInset: rootFloatingChromeInset
                    )
                case .profile:
                    MyProfileView(
                        profile: profile,
                        selectedTab: selectedTabBinding,
                        selectedProfileTab: $selectedProfileTab,
                        headerInset: rootFloatingChromeInset,
                        onOpenFriendsSearch: { openFriendSearch() },
                        onOpenFriendsQR: { pushSocialDestination(.qrProfile) },
                        onOpenFriendUsername: { username in
                            pushSocialDestination(.friendProfile(username: username))
                        },
                        onSelectFriendForTrade: { friend in
                            openSeededTradeBuilder(with: friend)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        handleTabSwipe(translation: value.translation)
                    }
            )
        }
    }

    private func handleTabSwipe(translation: CGSize) {
        let horizontal = translation.width
        let vertical = translation.height
        guard abs(horizontal) > abs(vertical) else { return }
        guard abs(horizontal) > 56 else { return }
        if horizontal < 0 {
            moveSelectedTab(by: 1)
        } else {
            moveSelectedTab(by: -1)
        }
    }

    private func moveSelectedTab(by offset: Int) {
        let tabs = SocialTab.allCases
        guard let currentIndex = tabs.firstIndex(of: selectedTab) else { return }
        let nextIndex = currentIndex + offset
        guard tabs.indices.contains(nextIndex) else { return }
        Haptics.lightImpact()
        selectedTabBinding.wrappedValue = tabs[nextIndex]
    }

    private func handleGoogleSignIn() async {
        errorMessage = nil
        do {
            try await services.socialAuth.signInWithGoogleOAuth()
            await services.socialPush.updateRegistrationState()
            await refreshProfileIfNeeded()
            await MainActor.run {
                profilePopoverPath = NavigationPath()
                if profile == nil {
                    profilePopoverPath.append(AccountProfileView.Destination.editProfile)
                }
                showAccountProfile = true
            }
        } catch let error as GoogleOAuthSession.OAuthError {
            if case .cancelled = error { return }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
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
            selectedTabBinding.wrappedValue = .feed
        case .friends, .friendRequests:
            selectedTabBinding.wrappedValue = .friends
        case .profile(let username):
            if profile == nil {
                profilePopoverPath = NavigationPath()
                profilePopoverPath.append(AccountProfileView.Destination.editProfile)
                showAccountProfile = true
            } else {
                selectedTabBinding.wrappedValue = .profile
                socialNavigationPath = NavigationPath()
                pushSocialDestination(.friendProfile(username: username))
            }
        case .content(let id):
            selectedTabBinding.wrappedValue = .feed
            guard let sharedContent = try? await services.socialShare.fetchSharedContent(id: id) else { return }
            deepLinkedCommentsContent = nil
            deepLinkedSharedContent = sharedContent
        case .post(let id):
            selectedTabBinding.wrappedValue = .feed
            guard let sharedContent = try? await services.socialShare.fetchSharedContent(id: id) else { return }
            deepLinkedSharedContent = nil
            deepLinkedCommentsContent = feedContentSummary(from: sharedContent)
        case .comment(let id):
            selectedTabBinding.wrappedValue = .feed
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
            selectedTabBinding.wrappedValue = .feed
            if let sharedContent = try? await services.socialShare.fetchSharedContent(id: id) {
                deepLinkedCommentsContent = nil
                deepLinkedSharedContent = sharedContent
                return
            }
            guard let contentID = try? await services.socialFeed.fetchContentID(forWishlistMatchID: id) else { return }
            guard let sharedContent = try? await services.socialShare.fetchSharedContent(id: contentID) else { return }
            deepLinkedCommentsContent = nil
            deepLinkedSharedContent = sharedContent
        case .trade(let id):
            selectedTabBinding.wrappedValue = .trades
            socialNavigationPath = NavigationPath()
            pushSocialDestination(.tradeDetail(tradeID: id))
        case .tradesList:
            selectedTabBinding.wrappedValue = .trades
            socialNavigationPath = NavigationPath()
            isNavigationActive?.wrappedValue = false
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
            brand: sharedContent.brand,
            updatedAt: sharedContent.updatedAt
        )
    }

    private func handleChromeActionRequest() {
        guard let request = chromeActionRequest?.wrappedValue else { return }
        switch request.action {
        case .newPost:
            presentNewPost()
        case .addFriend:
            presentFriendSearch()
        case .newTrade:
            presentStartTradeSheet()
        case .editProfile:
            editProfile()
        }
        chromeActionRequest?.wrappedValue = nil
    }

    private func presentNewPost() {
        isNewPostPresented = true
    }

    private func presentFriendSearch() {
        selectedTabBinding.wrappedValue = .friends
        isFriendSearchSheetPresented = true
    }

    private func openFriendSearch() {
        selectedTabBinding.wrappedValue = .friends
        pushSocialDestination(.search)
    }

    private func startNewTrade() {
        presentStartTradeSheet()
    }

    private func presentStartTradeSheet() {
        services.pendingTradeSeed = nil
        services.isCreatingNewTrade = true
        selectedTabBinding.wrappedValue = .trades
        isStartTradeSheetPresented = true
    }

    private func editProfile() {
        profilePopoverPath.append(AccountProfileView.Destination.editProfile)
        showAccountProfile = true
    }

    private func updateNavigationActiveState() {
        isNavigationActive?.wrappedValue = socialNavigationPath.count > 0
    }

    private func pushSocialDestination(_ destination: SocialDestination) {
        isNavigationActive?.wrappedValue = true
        socialNavigationPath.append(destination)
    }

    private func handleStartTradeSheetDismiss() {
        guard let friend = pendingTradeSheetFriend else {
            services.pendingTradeSeed = nil
            services.isCreatingNewTrade = false
            return
        }
        pendingTradeSheetFriend = nil
        openSeededTradeBuilder(with: friend)
    }

    private func openSeededTradeBuilder(with friend: SocialProfile) {
        // Always clear both trade-initiation flags regardless of path taken below.
        services.isCreatingNewTrade = false

        guard let seed = services.pendingTradeSeed else {
            // No pre-seeded card (came from Trade Wall + button) — open a blank builder.
            pushSocialDestination(
                .tradeBuilder(
                    receiverID: friend.id,
                    theirCards: [],
                    myCards: []
                )
            )
            return
        }

        let item = TradeItem(
            id: UUID(),
            tradeID: UUID(),
            ownerID: friend.id,
            cardID: seed.cardID,
            variantKey: "normal",
            quantity: 1,
            createdAt: nil
        )
        let (theirCards, myCards): ([TradeItem], [TradeItem]) = {
            switch seed.preferredSide {
            case .mySide:
                return ([], [item])
            case .theirSide:
                return ([item], [])
            }
        }()
        services.pendingTradeSeed = nil
        pushSocialDestination(
            .tradeBuilder(
                receiverID: friend.id,
                theirCards: theirCards,
                myCards: myCards
            )
        )
    }

    private var profilePopover: some View {
        NavigationStack(path: $profilePopoverPath) {
            AccountProfileView(
                navigationPath: $profilePopoverPath,
                isPresented: $showAccountProfile,
                externalProfile: $profile
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct SocialHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 52
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
