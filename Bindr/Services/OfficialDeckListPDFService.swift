import Foundation
import UIKit

enum OfficialDeckListDivision: String, CaseIterable, Identifiable, Sendable {
    case junior = "Junior"
    case seniors = "Seniors"
    case masters = "Masters"

    var id: String { rawValue }
}

struct OfficialDeckListPlayerInfo: Sendable {
    var playerName: String
    var playerID: String
    var birthdate: Date
    var division: OfficialDeckListDivision
}

enum OfficialDeckListPDFService {
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 50
    private static let bodyFontSize: CGFloat = 11
    private static let titleFontSize: CGFloat = 16
    private static let lineSpacing: CGFloat = 2

    static func generatePDF(
        playerInfo: OfficialDeckListPlayerInfo,
        formatDisplayName: String,
        deckListBody: String
    ) throws -> Data {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none

        var header = "OFFICIAL DECK LIST\n\n"
        header += "Player Name: \(playerInfo.playerName.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        header += "Player ID: \(playerInfo.playerID.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        header += "Birthdate: \(dateFormatter.string(from: playerInfo.birthdate))\n"
        header += "Division: \(playerInfo.division.rawValue)\n"
        header += "Format: \(formatDisplayName)\n\n"

        let fullText = header + deckListBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = fullText.components(separatedBy: .newlines)

        let pageRect = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { context in
            let bodyFont = UIFont.systemFont(ofSize: bodyFontSize)
            let titleFont = UIFont.boldSystemFont(ofSize: titleFontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = lineSpacing

            let textWidth = pageSize.width - margin * 2
            let maxY = pageSize.height - margin
            var y = margin

            func beginPageIfNeeded(neededHeight: CGFloat) {
                if y + neededHeight > maxY {
                    context.beginPage()
                    y = margin
                }
            }

            context.beginPage()

            for (index, line) in lines.enumerated() {
                let isTitle = index == 0 && line == "OFFICIAL DECK LIST"
                let font = isTitle ? titleFont : bodyFont
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .paragraphStyle: paragraph,
                    .foregroundColor: UIColor.black
                ]
                let attributed = NSAttributedString(string: line.isEmpty ? " " : line, attributes: attrs)
                let bounding = attributed.boundingRect(
                    with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let lineHeight = ceil(bounding.height) + lineSpacing
                beginPageIfNeeded(neededHeight: lineHeight)
                attributed.draw(in: CGRect(x: margin, y: y, width: textWidth, height: lineHeight))
                y += lineHeight
            }
        }
    }

    static func writeTemporaryPDF(data: Data, playerName: String) throws -> URL {
        let sanitized = playerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let base = sanitized.isEmpty ? "DeckList" : sanitized
        let filename = "OfficialDeckList-\(base).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
