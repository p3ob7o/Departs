import Foundation
import CoreLocation

struct GeoJSONLineString: Codable, Hashable {
    let type: String
    let coordinates: [[Double]]

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }
}

struct WalkingRoute: Codable, Hashable {
    let geometry: GeoJSONLineString
    let duration: Double
    let distance: Double

    var walkingMinutes: Int {
        Int((duration / 60).rounded())
    }
}
