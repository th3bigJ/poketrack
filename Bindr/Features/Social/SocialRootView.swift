import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct SocialRootView: View {
    private enum ProfilePopoverDestination: Hashable {
        case editProfile
    }

    @Environment(AppServices.self) private var services

    @State private var profile: SocialProfile?
    @State private var isProfileLoading = false
    @State private var errorMessage: String?
    @State private var showAccountProfile = false
    @State private var profilePopoverPath = NavigationPath()
    @State private var currentNonce: String?

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
        }
        .onChange(of: services.socialAuth.authState) { _, state in
            Task { await refreshProfileIfNeeded() }
            if state == .signedOut {
                profilePopoverPath = NavigationPath()
                showAccountProfile = false
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
        ContentUnavailableView(
            "Social Feed Coming Soon",
            systemImage: "person.2",
            description: Text("Use the profile button in the top-right to manage your social profile.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var profilePopover: some View {
        NavigationStack(path: $profilePopoverPath) {
            profilePopoverHome
                .navigationDestination(for: ProfilePopoverDestination.self) { destination in
                    switch destination {
                    case .editProfile:
                        EditProfileView(existingProfile: profile) { username, displayName, bio in
                            if profile == nil {
                                profile = try await services.socialProfile.saveProfile(
                                    username: username,
                                    displayName: displayName,
                                    bio: bio
                                )
                            } else {
                                profile = try await services.socialProfile.updateProfile(
                                    displayName: displayName,
                                    bio: bio
                                )
                            }
                            profilePopoverPath = NavigationPath()
                        }
                    }
                }
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

    @ViewBuilder
    private var profilePopoverHome: some View {
        switch services.socialAuth.authState {
        case .signedOut:
            List {
                Section {
                    Text("Sign in with Apple from the Social page to manage your social profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        case .signedIn:
            if let profile {
                MyProfileView(
                    profile: profile,
                    onEditTapped: { profilePopoverPath.append(ProfilePopoverDestination.editProfile) },
                    onSignOutTapped: {
                        services.socialAuth.signOut()
                        self.profile = nil
                        profilePopoverPath = NavigationPath()
                        showAccountProfile = false
                    }
                )
            } else {
                List {
                    Section {
                        Text("Create your social profile to start using social features.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Create Profile") {
                            profilePopoverPath.append(ProfilePopoverDestination.editProfile)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Section {
                        Button("Sign Out", role: .destructive) {
                            services.socialAuth.signOut()
                            self.profile = nil
                            profilePopoverPath = NavigationPath()
                            showAccountProfile = false
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Profile")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
