import Foundation

/// Persists Create Deck List player fields on device for reuse across decks.
enum OfficialDeckListPlayerInfoStore {
    static let rememberPreferenceKey = "official_deck_list_remember_player_info"
    private static let rememberKey = rememberPreferenceKey
    private static let nameKey = "official_deck_list_player_name"
    private static let idKey = "official_deck_list_player_id"
    private static let birthdateKey = "official_deck_list_player_birthdate"
    private static let divisionKey = "official_deck_list_player_division"

    static var rememberPlayerInfo: Bool {
        get { UserDefaults.standard.bool(forKey: rememberKey) }
        set { UserDefaults.standard.set(newValue, forKey: rememberKey) }
    }

    static func loadPlayerInfo() -> OfficialDeckListPlayerInfo? {
        guard rememberPlayerInfo else { return nil }
        let name = UserDefaults.standard.string(forKey: nameKey) ?? ""
        let playerID = UserDefaults.standard.string(forKey: idKey) ?? ""
        let birthInterval = UserDefaults.standard.object(forKey: birthdateKey) as? TimeInterval
        let divisionRaw = UserDefaults.standard.string(forKey: divisionKey)
        let division = divisionRaw.flatMap(OfficialDeckListDivision.init(rawValue:)) ?? .masters

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !playerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let birthInterval
        else { return nil }

        return OfficialDeckListPlayerInfo(
            playerName: name,
            playerID: playerID,
            birthdate: Date(timeIntervalSince1970: birthInterval),
            division: division
        )
    }

    static func savePlayerInfo(_ info: OfficialDeckListPlayerInfo) {
        UserDefaults.standard.set(info.playerName, forKey: nameKey)
        UserDefaults.standard.set(info.playerID, forKey: idKey)
        UserDefaults.standard.set(info.birthdate.timeIntervalSince1970, forKey: birthdateKey)
        UserDefaults.standard.set(info.division.rawValue, forKey: divisionKey)
    }

    static func clearPlayerInfo() {
        UserDefaults.standard.removeObject(forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: birthdateKey)
        UserDefaults.standard.removeObject(forKey: divisionKey)
    }
}
