import Foundation
import Observation

@Observable
@MainActor
final class SocialAuthService {
    enum AuthState: Equatable {
        case signedOut
        case signedIn(userID: UUID, email: String?)
    }

    private struct AuthResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let user: AuthUser?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case user
        }
    }

    private struct AuthUser: Decodable {
        let id: UUID
        let email: String?
    }

    private struct AuthErrorPayload: Decodable {
        let errorDescription: String?
        let msg: String?

        enum CodingKeys: String, CodingKey {
            case errorDescription = "error_description"
            case msg
        }
    }

    enum SocialAuthError: LocalizedError {
        case missingConfiguration
        case invalidResponse
        case missingSession
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Supabase social config is missing from Info.plist."
            case .invalidResponse:
                return "Could not understand the authentication response."
            case .missingSession:
                return "Authentication completed but no session was returned. Check email confirmation settings in Supabase Auth."
            case .requestFailed(let message):
                return message
            }
        }
    }

    private(set) var authState: AuthState = .signedOut
    private(set) var isBusy = false
    private(set) var statusMessage: String?

    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    private var baseURL: URL? { AppConfiguration.supabaseURL }
    private var publishableKey: String { AppConfiguration.supabasePublishableKey }

    func signUp(email: String, password: String) async throws {
        try ensureConfigured()
        isBusy = true
        defer { isBusy = false }
        statusMessage = "Creating account…"

        let payload = ["email": email, "password": password]
        let response: AuthResponse = try await sendAuthRequest(
            path: "/auth/v1/signup",
            method: "POST",
            body: payload
        )
        try applyAuthResponse(response)
        statusMessage = "Account created"
    }

    func signIn(email: String, password: String) async throws {
        try ensureConfigured()
        isBusy = true
        defer { isBusy = false }
        statusMessage = "Signing in…"

        let payload = ["email": email, "password": password]
        let response: AuthResponse = try await sendAuthRequest(
            path: "/auth/v1/token?grant_type=password",
            method: "POST",
            body: payload
        )
        try applyAuthResponse(response)
        statusMessage = "Signed in"
    }

    func signInWithApple(idToken: String, rawNonce: String?, appleUserIdentifier: String?) async throws {
        try ensureConfigured()
        isBusy = true
        defer { isBusy = false }
        statusMessage = "Signing in with Apple…"

        var payload: [String: String] = [
            "provider": "apple",
            "id_token": idToken
        ]
        if let rawNonce, !rawNonce.isEmpty {
            payload["nonce"] = rawNonce
        }

        let response: AuthResponse = try await sendAuthRequest(
            path: "/auth/v1/token?grant_type=id_token",
            method: "POST",
            body: payload
        )
        try applyAuthResponse(response)
        if let appleUserIdentifier, !appleUserIdentifier.isEmpty {
            KeychainStorage.saveAppleUserIdentifier(appleUserIdentifier)
        }
        statusMessage = "Signed in with Apple"
    }

    func restoreSession() async {
        guard let refreshToken = KeychainStorage.readSocialRefreshToken() else {
            return
        }
        guard let storedUserID = KeychainStorage.readSocialUserID() else {
            KeychainStorage.deleteSocialSession()
            return
        }

        do {
            try ensureConfigured()
            let payload = ["refresh_token": refreshToken]
            let response: AuthResponse = try await sendAuthRequest(
                path: "/auth/v1/token?grant_type=refresh_token",
                method: "POST",
                body: payload
            )

            if let token = response.accessToken {
                accessToken = token
            } else {
                accessToken = KeychainStorage.readSocialAccessToken()
            }
            self.refreshToken = response.refreshToken ?? refreshToken
            authState = .signedIn(userID: response.user?.id ?? storedUserID, email: response.user?.email)
            if let accessToken, let latestRefresh = self.refreshToken {
                KeychainStorage.saveSocialSession(
                    accessToken: accessToken,
                    refreshToken: latestRefresh,
                    userID: response.user?.id ?? storedUserID
                )
            }
        } catch {
            signOut(clearRemoteSession: false)
        }
    }

    func signOut(clearRemoteSession: Bool = true) {
        let existingAccessToken = accessToken
        accessToken = nil
        refreshToken = nil
        authState = .signedOut
        statusMessage = nil
        KeychainStorage.deleteSocialSession()

        guard clearRemoteSession, let existingAccessToken else { return }
        Task {
            try? await sendSignOutRequest(accessToken: existingAccessToken)
        }
    }

    private func applyAuthResponse(_ response: AuthResponse) throws {
        guard
            let accessToken = response.accessToken,
            let refreshToken = response.refreshToken,
            let user = response.user
        else {
            throw SocialAuthError.missingSession
        }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        authState = .signedIn(userID: user.id, email: user.email)
        KeychainStorage.saveSocialSession(accessToken: accessToken, refreshToken: refreshToken, userID: user.id)
    }

    private func ensureConfigured() throws {
        guard baseURL != nil, !publishableKey.isEmpty else {
            throw SocialAuthError.missingConfiguration
        }
    }

    private func sendSignOutRequest(accessToken: String) async throws {
        let url = try makeURL(path: "/auth/v1/logout")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    private func sendAuthRequest<T: Decodable>(path: String, method: String, body: [String: String]) async throws -> T {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SocialAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(AuthErrorPayload.self, from: data) {
                throw SocialAuthError.requestFailed(payload.errorDescription ?? payload.msg ?? "Authentication failed with status \(http.statusCode).")
            }
            throw SocialAuthError.requestFailed("Authentication failed with status \(http.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func makeURL(path: String) throws -> URL {
        guard let baseURL else { throw SocialAuthError.missingConfiguration }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SocialAuthError.invalidResponse
        }
        return url
    }
}
