import Foundation
import CoreLocation

struct Coordinate: Codable, Hashable {
    let lat: Double
    let lon: Double

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct NearbyStop: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: TransportType
    let lines: [LineInfo]
    let location: Coordinate
    let distance: Int?
}

struct StopLineSelection: Identifiable, Hashable {
    let stop: NearbyStop
    let line: LineInfo
    let lineIndex: Int

    var id: String {
        "\(stop.id)::\(lineIndex)::\(line.id)"
    }
}

extension NearbyStop {
    var lineSelections: [StopLineSelection] {
        lines.enumerated().map { index, line in
            StopLineSelection(stop: self, line: line, lineIndex: index)
        }
    }
}
