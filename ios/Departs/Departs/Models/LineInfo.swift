import Foundation

struct LineInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let direction: String
    let type: TransportType
}
