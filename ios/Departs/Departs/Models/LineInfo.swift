import Foundation

struct LineInfo: Codable, Identifiable, Hashable {
    let name: String
    let direction: String
    let type: TransportType

    var id: String { "\(name)::\(direction)" }
}
