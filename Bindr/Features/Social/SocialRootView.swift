import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct SocialRootView: View {
    private enum SocialSection: String, CaseIterable, Identifiable {
        case feed
        case friends

        var id: String { rawValue }
        var title: String {
            switch self {
            case .feed: return "Feed"
            case .friends: return "Friends"
            }
        }
    }

    private enum ProfilePopoverDestination: Hashable {
        case editProfile
    }

    private enum SocialDestination: Hashable {
        case search
        case qrProfile
        case friendProfile(username: String)
    }

    @Environment(AppServices.self) private var services

    @State private var profile: SocialProfile?
    @State private var isProfileLoading = false
    @State private var errorMessage: String?
    @State private var showAccountProfile = false
    @State private var profilePopoverPath = NavigationPath()
    @State private var socialNavigationPath = NavigationPath()
    @State private var currentNonce: String?
    @State private var selectedSection: SocialSection = .feed

    private var isConfigured: Bool {
        AppConfiguration.supabaseURL != nil && !AppConfiguration.supabasePublishableKey.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            socialHeader
            content
        }
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAccountProfile) {
            profilePopover
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                selectedSection = .feed
            }
        }
    }

    private var socialHeader: some View {
        ZStack {
            Text("Social")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                Spacer(minLength: 0)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                VStack(spacing: 12) {
                    Picker("Social section", selection: $selectedSection) {
                        ForEach(SocialSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Group {
                        switch selectedSection {
                        case .feed:
                            FeedView()
                        case .friends:
                            FriendsListView(
                                onOpenSearch: { socialNavigationPath.append(SocialDestination.search) },
                                onOpenQR: { socialNavigationPath.append(SocialDestination.qrProfile) },
                                onOpenUsername: { username in
                                    socialNavigationPath.append(SocialDestination.friendProfile(username: username))
                                }
                            )
                        }
                    }
                }
                .navigationTitle(selectedSection.title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: SocialDestination.self) { destination in
                    switch destination {
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
                    profilePopoverPath.append(ProfilePopoverDestination.editProfile)
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
        guard let username = services.socialFriend.queuedProfileUsername else { return }
        if profile == nil {
            profilePopoverPath = NavigationPath()
            profilePopoverPath.append(ProfilePopoverDestination.editProfile)
            showAccountProfile = true
        } else {
            _ = services.socialFriend.consumeQueuedProfileUsername()
            socialNavigationPath = NavigationPath()
            socialNavigationPath.append(SocialDestination.friendProfile(username: username))
        }
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
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
