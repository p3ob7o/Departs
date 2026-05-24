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

extension NearbyStop {
    var lineSummary: String? {
        let lineNames = sortedUnique(lines.map(\.name))
        guard let firstLineName = lineNames.first else { return nil }

        if lineNames.count == 1 {
            let directions = unique(lines.map(\.direction))
            if directions.count == 1, let direction = directions.first {
                return "\(firstLineName) \u{2192} \(direction)"
            }

            if directions.count == 2 {
                return "\(firstLineName) \u{2192} \(directions.joined(separator: ", "))"
            }

            return firstLineName
        }

        return lineNames.joined(separator: ", ")
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func sortedUnique(_ values: [String]) -> [String] {
        unique(values).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
