import XCTest
@testable import Departs

final class DepartsTests: XCTestCase {

    // MARK: - Model Decoding

    func testNearbyStopDecoding() throws {
        let json = """
        {
            "id": "stop-1",
            "name": "Alexanderplatz",
            "type": "subway",
            "lines": [{"name": "U2", "direction": "Ruhleben", "type": "subway"}],
            "location": {"lat": 52.5219, "lon": 13.4132}
        }
        """.data(using: .utf8)!

        let stop = try JSONDecoder().decode(NearbyStop.self, from: json)
        XCTAssertEqual(stop.id, "stop-1")
        XCTAssertEqual(stop.name, "Alexanderplatz")
        XCTAssertEqual(stop.type, .subway)
        XCTAssertEqual(stop.lines.count, 1)
        XCTAssertNil(stop.distance)
    }

    func testDepartureDecoding() throws {
        let json = """
        {"time": "2026-02-17T14:45:00Z", "realTime": true, "delay": 120}
        """.data(using: .utf8)!

        let dep = try JSONDecoder().decode(Departure.self, from: json)
        XCTAssertEqual(dep.time, "2026-02-17T14:45:00Z")
        XCTAssertTrue(dep.realTime)
        XCTAssertEqual(dep.delay, 120)
    }

    func testWalkingRouteDecoding() throws {
        let json = """
        {
            "geometry": {
                "type": "LineString",
                "coordinates": [[13.4050, 52.5200], [13.4132, 52.5219]]
            },
            "duration": 180,
            "distance": 250
        }
        """.data(using: .utf8)!

        let route = try JSONDecoder().decode(WalkingRoute.self, from: json)
        XCTAssertEqual(route.walkingMinutes, 3)
        XCTAssertEqual(route.geometry.clCoordinates.count, 2)
    }

    // MARK: - TimeFormatter

    func testFormatTime() {
        let result = TimeFormatter.formatTime("2026-02-17T14:45:00Z")
        // Result depends on timezone, but should contain a time string
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - StopPalette

    func testPaletteCount() {
        XCTAssertEqual(StopPalette.colors.count, 10)
    }

    func testPaletteWraps() {
        // Index 10 should wrap to index 0
        let color0 = StopPalette.color(at: 0)
        let color10 = StopPalette.color(at: 10)
        XCTAssertEqual(color0, color10)
    }

    // MARK: - TransportType

    func testTransportLabels() {
        XCTAssertEqual(TransportType.subway.label, "M")
        XCTAssertEqual(TransportType.tram.label, "T")
        XCTAssertEqual(TransportType.bus.label, "B")
        XCTAssertEqual(TransportType.rail.label, "R")
    }

    func testTransportDisplayNames() {
        XCTAssertEqual(TransportType.subway.displayName, "Subway")
        XCTAssertEqual(TransportType.tram.displayName, "Tram")
        XCTAssertEqual(TransportType.bus.displayName, "Bus")
        XCTAssertEqual(TransportType.rail.displayName, "Rail")
    }
}
