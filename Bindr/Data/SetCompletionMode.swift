import Foundation

/// How set / Pokédex completion is measured in Browse.
enum SetCompletionMode: String, CaseIterable, Equatable, Sendable {
    case full
    case master
    case grandMaster

    var usesVariantGrid: Bool {
        self != .full
    }

    var chipLabel: String {
        switch self {
        case .full: return "Full Set"
        case .master: return "Master Set"
        case .grandMaster: return "Grand Master"
        }
    }

    var listValueLabel: String {
        switch self {
        case .full: return "Full Set Value"
        case .master: return "Master Set Value"
        case .grandMaster: return "Grand Master Value"
        }
    }

    var completionTitle: String {
        switch self {
        case .full: return "Set Completion"
        case .master: return "Master Set Completion"
        case .grandMaster: return "Grand Master Completion"
        }
    }

    var dexCompletionTitle: String {
        switch self {
        case .full: return "Card Completion"
        case .master: return "Master Set Completion"
        case .grandMaster: return "Grand Master Completion"
        }
    }

    var valueCaption: String {
        switch self {
        case .full: return "SET VALUE"
        case .master: return "MASTER VALUE"
        case .grandMaster: return "GRAND MASTER VALUE"
        }
    }

    var dexValueCaption: String {
        switch self {
        case .full: return "CARD VALUE"
        case .master: return "MASTER VALUE"
        case .grandMaster: return "GRAND MASTER VALUE"
        }
    }
}
