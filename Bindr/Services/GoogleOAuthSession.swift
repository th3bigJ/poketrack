import AuthenticationServices
import Foundation
import UIKit

/// Presents Supabase Google OAuth in `ASWebAuthenticationSession` and returns
/// tokens from the `bindr://auth-callback` redirect. Requires the redirect URL
/// to be allow-listed in the Supabase Auth settings.
@MainActor
enum GoogleOAuthSession {
    enum OAuthError: LocalizedError {
        case missingConfiguration
        case cancelled
        case invalidCallback
        case missingTokens

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Google sign-in is not configured for this build."
            case .cancelled:
                return "Google sign-in was cancelled."
            case .invalidCallback:
                return "Could not read the Google sign-in callback."
            case .missingTokens:
                return "Google sign-in completed but no session tokens were returned."
            }
        }
    }

    struct Tokens {
        let accessToken: String
        let refreshToken: String
    }

    static func signIn() async throws -> Tokens {
        guard
            let baseURL = AppConfiguration.supabaseURL,
            !AppConfiguration.supabasePublishableKey.isEmpty
        else {
            throw OAuthError.missingConfiguration
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: AppConfiguration.googleOAuthRedirectURL.absoluteString)
        ]
        guard let authURL = components?.url else {
            throw OAuthError.missingConfiguration
        }

        let callbackURL = try await presentWebAuth(url: authURL)
        return try parseTokens(from: callbackURL)
    }

    private static func presentWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfiguration.oauthRedirectScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthPresentationContext.shared
            WebAuthPresentationContext.shared.retainedSession = session
            guard session.start() else {
                WebAuthPresentationContext.shared.retainedSession = nil
                continuation.resume(throwing: OAuthError.missingConfiguration)
                return
            }
        }
    }

    private static func parseTokens(from url: URL) throws -> Tokens {
        let fragment = url.fragment ?? ""
        let query = url.query ?? ""
        let params = parseKeyValuePairs(from: fragment.isEmpty ? query : fragment)

        guard
            let accessToken = params["access_token"],
            let refreshToken = params["refresh_token"]
        else {
            throw OAuthError.missingTokens
        }
        return Tokens(accessToken: accessToken, refreshToken: refreshToken)
    }

    private static func parseKeyValuePairs(from raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].removingPercentEncoding ?? parts[0]
            let value = parts[1].removingPercentEncoding ?? parts[1]
            result[key] = value
        }
        return result
    }
}

@MainActor
private final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()
    var retainedSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        retainedSession = nil
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let window = scenes.first?.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
