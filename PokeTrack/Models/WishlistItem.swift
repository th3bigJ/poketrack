import Foundation
import SwiftData

@Model
final class WishlistItem {
    var id: UUID = UUID()
    var masterCardId: String = ""
    var setCode: String = ""
    var priority: Int = 3
    var targetConditionId: String?
    var targetPrinting: String?
    var notes: String?
    var addedAt: Date = Date()

    init(
        masterCardId: String,
        setCode: String,
        priority: Int = 3,
        addedAt: Date = .now
    ) {
        self.id = UUID()
        self.masterCardId = masterCardId
        self.setCode = setCode
        self.priority = priority
        self.addedAt = addedAt
    }
}
