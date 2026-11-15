import Foundation
import CoreLocation

struct Coordinate: Codable, Hashable {
    let lat: Double
    let lon: Double

    var clLocationCoordinate2D: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func distance(to other: Coordinate) -> Double {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: other.lat, longitude: other.lon))
    }

    var isValid: Bool {
        lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
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

struct StopLineSelection: Codable, Identifiable, Hashable {
    let stop: NearbyStop
    let line: LineInfo
    let lineIndex: Int

    var id: String {
        // Provider ordering can change between refreshes. Pins identify the service, not its array index.
        [stop.id, line.type.rawValue, line.name, line.direction]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }
}

extension NearbyStop {
    var lineSelections: [StopLineSelection] {
        var seen = Set<String>()
        return lines.enumerated().map { index, line in
            StopLineSelection(stop: self, line: line, lineIndex: index)
        }.filter { seen.insert($0.id).inserted }
    }
}
