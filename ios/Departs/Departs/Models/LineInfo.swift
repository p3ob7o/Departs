import Foundation

struct LineInfo: Codable, Identifiable, Hashable {
    let name: String
    let direction: String
    let type: TransportType

    var id: String { "\(name)::\(direction)" }

    /// Shortens the provider's London subway headsign for display.
    var displayDirection: String {
        guard type == .subway else { return direction }
        let trimmed = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suffix = trimmed.range(of: " Underground Station", options: [.caseInsensitive, .backwards, .anchored]) else {
            return direction
        }
        return trimmed[..<suffix.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    /// What the app shows for the line: its number and letter identifier only.
    /// A provider can put an operator or brand in front, as in "FlixBus N70";
    /// the badge reads "N70". Pins, links and requests keep `name`.
    var shortName: String { Self.identifier(of: name) }

    /// Keeps the words that carry a number, with a one- or two-letter prefix
    /// written apart from its number ("S 1", "RE 5"). A name with no number,
    /// or a single word, is shown as it is.
    static func identifier(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return words.first ?? name }
        var kept = IndexSet()
        for (index, word) in words.enumerated() where word.contains(where: \.isNumber) {
            if index > 0, words[index - 1].count <= 2, words[index - 1].allSatisfy(\.isLetter) { kept.insert(index - 1) }
            kept.insert(index)
        }
        return kept.isEmpty ? words.joined(separator: " ") : kept.map { words[$0] }.joined(separator: " ")
    }
}
