import Foundation
import CoreLocation

enum PreviewData {
    static let userCoordinate = Coordinate(lat: 52.5200, lon: 13.4050)

    static let stops: [NearbyStop] = [
        NearbyStop(
            id: "stop-1",
            name: "Alexanderplatz",
            type: .subway,
            lines: [
                LineInfo(name: "U2", direction: "Ruhleben", type: .subway),
                LineInfo(name: "U5", direction: "Hauptbahnhof", type: .subway),
            ],
            location: Coordinate(lat: 52.5219, lon: 13.4132),
            distance: 150
        ),
        NearbyStop(
            id: "stop-2",
            name: "Hackescher Markt",
            type: .rail,
            lines: [
                LineInfo(name: "S5", direction: "Westkreuz", type: .rail),
            ],
            location: Coordinate(lat: 52.5225, lon: 13.4024),
            distance: 200
        ),
        NearbyStop(
            id: "stop-3",
            name: "Mollstraße",
            type: .tram,
            lines: [
                LineInfo(name: "M2", direction: "Heinersdorf", type: .tram),
            ],
            location: Coordinate(lat: 52.5245, lon: 13.4220),
            distance: 320
        ),
        NearbyStop(
            id: "stop-4",
            name: "Memhardstraße",
            type: .bus,
            lines: [
                LineInfo(name: "100", direction: "Zoologischer Garten", type: .bus),
            ],
            location: Coordinate(lat: 52.5230, lon: 13.4100),
            distance: 80
        ),
    ]

    static let departures: [Departure] = [
        Departure(time: "2026-02-17T14:45:00Z", realTime: true, delay: 0),
        Departure(time: "2026-02-17T14:52:00Z", realTime: true, delay: 120),
        Departure(time: "2026-02-17T15:00:00Z", realTime: false, delay: nil),
        Departure(time: "2026-02-17T15:15:00Z", realTime: true, delay: 60),
    ]

    static let walkingRoute = WalkingRoute(
        geometry: GeoJSONLineString(
            type: "LineString",
            coordinates: [
                [13.4050, 52.5200],
                [13.4080, 52.5210],
                [13.4100, 52.5215],
                [13.4132, 52.5219],
            ]
        ),
        duration: 180,
        distance: 250
    )
}
