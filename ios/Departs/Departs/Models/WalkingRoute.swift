import Foundation
import CoreLocation

struct GeoJSONLineString: Codable, Hashable {
    let type: String
    let coordinates: [[Double]]

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.compactMap {
            guard $0.count >= 2 else { return nil }
            let coordinate = Coordinate(lat: $0[1], lon: $0[0])
            return coordinate.isValid ? coordinate.clLocationCoordinate2D : nil
        }
    }
}

struct WalkingRoute: Codable, Hashable {
    let geometry: GeoJSONLineString
    let duration: Double
    let distance: Double

    var walkingMinutes: Int {
        guard duration.isFinite, duration >= 0 else { return 0 }
        return Int(ceil(duration / 60))
    }
}
