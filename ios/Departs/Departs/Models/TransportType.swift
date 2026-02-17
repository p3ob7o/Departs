import Foundation

enum TransportType: String, Codable, CaseIterable {
    case subway
    case tram
    case bus
    case rail

    var label: String {
        switch self {
        case .subway: "M"
        case .tram: "T"
        case .bus: "B"
        case .rail: "R"
        }
    }

    var displayName: String {
        switch self {
        case .subway: "Subway"
        case .tram: "Tram"
        case .bus: "Bus"
        case .rail: "Rail"
        }
    }
}
