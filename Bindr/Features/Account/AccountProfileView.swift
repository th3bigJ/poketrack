import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct AccountProfileView: View {
    @Environment(AppServices.self) private var services
    @Binding var navigationPath: NavigationPath
    @Binding var isPresented: Bool
    @Binding var externalProfile: SocialProfile?
    
    @State private var profile: SocialProfile?
    @State private var isProfileLoading = false
    @State private var errorMessage: String?
    @State private var currentNonce: String?
    
    enum Destination: Hashable {
        case editProfile
    }
    
    var body: some View {
        Group {
            if isProfileLoading || services.socialAuth.isBusy {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(services.socialAuth.statusMessage ?? "Loading profile…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch services.socialAuth.authState {
                case .signedOut:
                    signInView
                case .signedIn:
                    if let profile {
                        MyProfileView(
                            profile: profile,
                            onEditTapped: { navigationPath.append(Destination.editProfile) },
                            onSignOutTapped: {
                                services.socialAuth.signOut()
                                self.profile = nil
                                self.externalProfile = nil
                                navigationPath = NavigationPath()
                                isPresented = false
                            }
                        )
                    } else {
                        createProfilePrompt
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .editProfile:
                EditProfileView(existingProfile: profile) { payload in
                    try await handleProfileSave(payload: payload)
                }
            }
        }
        .task {
            await services.socialAuth.restoreSession()
            await refreshProfileIfNeeded()
        }
        .onChange(of: services.socialAuth.authState) { _, state in
            Task {
                await refreshProfileIfNeeded()
            }
            if state == .signedOut {
                navigationPath = NavigationPath()
                isPresented = false
            }
        }
    }
    
    // MARK: - Subviews
    
    private var signInView: some View {
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
    
    private var createProfilePrompt: some View {
        List {
            Section {
                Text("Create your social profile to start using social features.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button("Create Profile") {
                    navigationPath.append(Destination.editProfile)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Section {
                Button("Sign Out", role: .destructive) {
                    services.socialAuth.signOut()
                    self.profile = nil
                    navigationPath = NavigationPath()
                    isPresented = false
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Helpers
    
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
            externalProfile = profile
            if profile == nil {
                navigationPath.append(Destination.editProfile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func handleProfileSave(payload: SocialProfileFormPayload) async throws {
        print("[ProfileSave] Starting save. Profile exists: \(profile != nil)")
        print("[ProfileSave] Auth state: \(services.socialAuth.authState)")
        print("[ProfileSave] Access token present: \(services.socialAuth.accessToken != nil)")

        if profile == nil {
            print("[ProfileSave] → calling saveProfile (create)")
            let saved = try await services.socialProfile.saveProfile(
                username: payload.username,
                displayName: payload.displayName,
                bio: payload.bio,
                profileRoles: payload.profileRoles,
                favoritePokemonDex: payload.favoritePokemonDex,
                favoritePokemonName: payload.favoritePokemonName,
                favoritePokemonImageURL: payload.favoritePokemonImageURL,
                favoriteCardID: payload.favoriteCardID,
                favoriteCardName: payload.favoriteCardName,
                favoriteCardSetCode: payload.favoriteCardSetCode,
                favoriteCardImageURL: payload.favoriteCardImageURL,
                favoriteDeckArchetype: payload.favoriteDeckArchetype,
                isWishlistPublic: payload.isWishlistPublic,
                wishlistCardIDs: payload.wishlistCardIDs,
                avatarBackgroundColor: payload.avatarBackgroundColor,
                avatarOutlineStyle: payload.avatarOutlineStyle
            )
            print("[ProfileSave] saveProfile succeeded: \(saved.username)")
            profile = saved
        } else {
            print("[ProfileSave] → calling updateProfile")
            let updated = try await services.socialProfile.updateProfile(
                displayName: payload.displayName,
                bio: payload.bio,
                profileRoles: payload.profileRoles,
                favoritePokemonDex: payload.favoritePokemonDex,
                favoritePokemonName: payload.favoritePokemonName,
                favoritePokemonImageURL: payload.favoritePokemonImageURL,
                favoriteCardID: payload.favoriteCardID,
                favoriteCardName: payload.favoriteCardName,
                favoriteCardSetCode: payload.favoriteCardSetCode,
                favoriteCardImageURL: payload.favoriteCardImageURL,
                favoriteDeckArchetype: payload.favoriteDeckArchetype,
                isWishlistPublic: payload.isWishlistPublic,
                wishlistCardIDs: payload.wishlistCardIDs,
                avatarBackgroundColor: payload.avatarBackgroundColor,
                avatarOutlineStyle: payload.avatarOutlineStyle
            )
            print("[ProfileSave] updateProfile succeeded: \(updated.username)")
            profile = updated
        }
        
        externalProfile = profile
        
        // Refresh feed so my posts show the new avatar/colors
        try? await services.socialFeed.fetchFeed(refresh: true)
        
        // Dismiss the entire profile popover
        navigationPath = NavigationPath()
        isPresented = false
    }
    
    private func refreshProfileIfNeeded() async {
        guard case .signedIn = services.socialAuth.authState else {
            profile = nil
            return
        }
        isProfileLoading = true
        defer { isProfileLoading = false }
        do {
            profile = try await services.socialProfile.fetchMyProfile()
            externalProfile = profile
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
            if errorCode != errSecSuccess { fatalError("Unable to generate nonce.") }
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
}
