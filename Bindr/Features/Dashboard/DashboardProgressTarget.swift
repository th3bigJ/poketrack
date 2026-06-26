import Foundation

enum DashboardProgressTargetKind: String, Codable, CaseIterable, Sendable {
    case set
    case pokemon
}

struct DashboardProgressTarget: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: DashboardProgressTargetKind
    /// Lowercased set code when `kind == .set`.
    var setCode: String?
    var setName: String?
    var dexId: Int?
    var pokemonDisplayName: String?
    var completionMode: SetCompletionMode
    var addedAt: Date

    init(
        id: UUID = UUID(),
        kind: DashboardProgressTargetKind,
        setCode: String? = nil,
        setName: String? = nil,
        dexId: Int? = nil,
        pokemonDisplayName: String? = nil,
        completionMode: SetCompletionMode,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.setCode = setCode?.lowercased()
        self.setName = setName
        self.dexId = dexId
        self.pokemonDisplayName = pokemonDisplayName
        self.completionMode = completionMode
        self.addedAt = addedAt
    }

    var displayTitle: String {
        switch kind {
        case .set:
            return setName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? setName!
                : (setCode ?? "Set").uppercased()
        case .pokemon:
            return pokemonDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? pokemonDisplayName!
                : "Pokémon #\(dexId ?? 0)"
        }
    }
}

struct DashboardProgressTrackerStore: Equatable, Sendable {
    static let maxTargets = 8
    private static let defaultsKey = "dashboardProgressTargetsJSON"

    var targets: [DashboardProgressTarget] = []

    static func load() -> DashboardProgressTrackerStore {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([DashboardProgressTarget].self, from: data)
        else {
            return DashboardProgressTrackerStore()
        }
        return DashboardProgressTrackerStore(targets: decoded)
    }

    mutating func persist() {
        guard let data = try? JSONEncoder().encode(targets) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    mutating func add(_ target: DashboardProgressTarget) {
        targets.removeAll {
            $0.kind == target.kind
                && $0.setCode == target.setCode
                && $0.dexId == target.dexId
        }
        targets.insert(target, at: 0)
        if targets.count > Self.maxTargets {
            targets = Array(targets.prefix(Self.maxTargets))
        }
        persist()
    }

    mutating func remove(id: UUID) {
        targets.removeAll { $0.id == id }
        persist()
    }

    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard targets.indices.contains(index) else { continue }
            targets.remove(at: index)
        }
        persist()
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { targets[$0] }
        for index in source.sorted(by: >) {
            targets.remove(at: index)
        }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        targets.insert(contentsOf: moving, at: min(max(adjustedDestination, 0), targets.count))
        persist()
    }
}
