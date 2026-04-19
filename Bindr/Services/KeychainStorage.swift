import Foundation
import Security

enum KeychainStorage {
    private static let service = "app1xy.bindr"
    private static let appleUserAccount = "appleUserIdentifier"
    private static let socialAccessTokenAccount = "socialSupabaseAccessToken"
    private static let socialRefreshTokenAccount = "socialSupabaseRefreshToken"
    private static let socialUserIDAccount = "socialSupabaseUserID"

    static func saveAppleUserIdentifier(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: appleUserAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func readAppleUserIdentifier() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: appleUserAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAppleUserIdentifier() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: appleUserAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveSocialSession(accessToken: String, refreshToken: String, userID: UUID) {
        saveString(accessToken, account: socialAccessTokenAccount)
        saveString(refreshToken, account: socialRefreshTokenAccount)
        saveString(userID.uuidString, account: socialUserIDAccount)
    }

    static func readSocialAccessToken() -> String? {
        readString(account: socialAccessTokenAccount)
    }

    static func readSocialRefreshToken() -> String? {
        readString(account: socialRefreshTokenAccount)
    }

    static func readSocialUserID() -> UUID? {
        guard let raw = readString(account: socialUserIDAccount) else { return nil }
        return UUID(uuidString: raw)
    }

    static func deleteSocialSession() {
        delete(account: socialAccessTokenAccount)
        delete(account: socialRefreshTokenAccount)
        delete(account: socialUserIDAccount)
    }

    private static func saveString(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
