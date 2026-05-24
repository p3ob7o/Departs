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
        XCTAssertNil(dep.line)
    }

    func testDepartureDecodingWithLineMetadata() throws {
        let json = """
        {
            "time": "2026-02-17T14:45:00+02:00",
            "realTime": true,
            "delay": 120,
            "line": {
                "name": "U2",
                "direction": "Pankow",
                "type": "subway"
            }
        }
        """.data(using: .utf8)!

        let dep = try JSONDecoder().decode(Departure.self, from: json)

        XCTAssertEqual(dep.line?.name, "U2")
        XCTAssertEqual(dep.line?.direction, "Pankow")
        XCTAssertEqual(dep.line?.type, .subway)
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

    func testNearbyStopLineSummaryShowsAllUniqueRoutes() {
        let stop = NearbyStop(
            id: "skanstull-subway",
            name: "Skanstull",
            type: .subway,
            lines: [
                LineInfo(name: "17", direction: "Alvik", type: .subway),
                LineInfo(name: "17", direction: "Skarpnäck", type: .subway),
                LineInfo(name: "18", direction: "Farsta strand", type: .subway),
                LineInfo(name: "19", direction: "Hagsätra", type: .subway)
            ],
            location: Coordinate(lat: 59.30778, lon: 18.07583),
            distance: 120
        )

        XCTAssertEqual(stop.lineSummary, "17, 18, 19")
    }

    func testNearbyStopLineSummaryUsesNaturalRouteSorting() {
        let stop = NearbyStop(
            id: "skanstull-bus",
            name: "Skanstull",
            type: .bus,
            lines: [
                LineInfo(name: "164", direction: "Södersjukhuset", type: .bus),
                LineInfo(name: "3", direction: "Karolinska sjukhuset", type: .bus),
                LineInfo(name: "55", direction: "Finnberget", type: .bus),
                LineInfo(name: "57", direction: "Slussen", type: .bus),
                LineInfo(name: "66", direction: "Sofia", type: .bus),
                LineInfo(name: "74", direction: "Sickla udde", type: .bus),
                LineInfo(name: "94", direction: "Gullmarsplan", type: .bus),
                LineInfo(name: "96", direction: "Odenplan", type: .bus)
            ],
            location: Coordinate(lat: 59.30778, lon: 18.07583),
            distance: 80
        )

        XCTAssertEqual(stop.lineSummary, "3, 55, 57, 66, 74, 94, 96, 164")
    }

    func testNearbyStopLineSummaryKeepsDirectionForSingleRoute() {
        let stop = NearbyStop(
            id: "single-line",
            name: "skanstull",
            type: .bus,
            lines: [
                LineInfo(name: "68", direction: "Globen", type: .bus)
            ],
            location: Coordinate(lat: 59.30778, lon: 18.07583),
            distance: 60
        )

        XCTAssertEqual(stop.lineSummary, "68 \u{2192} Globen")
    }

    // MARK: - TimeFormatter

    func testFormatTimeUsesTimestampLocalClock() {
        let result = TimeFormatter.formatTime(
            "2026-02-17T14:45:00+02:00",
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalized = result.replacingOccurrences(of: "\u{202F}", with: " ")

        XCTAssertEqual(normalized, "2:45 PM")
    }

    // MARK: - APIService

    func testDepartureURLPercentEncodesStopId() throws {
        let url = try APIService.departuresURL(stopId: "stop/1?direction=A&B")

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "departs.vercel.app")
        XCTAssertEqual(url.path, "/api/departures")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "stop/1?direction=A&B")
    }

    // MARK: - ViewModels

    @MainActor
    func testNearbyStopsViewModelCachesStopColorsWhenStopsChange() async throws {
        let viewModel = NearbyStopsViewModel()
        let stops = [
            NearbyStop(
                id: "stop-1",
                name: "Central Station",
                type: .subway,
                lines: [LineInfo(name: "U2", direction: "Pankow", type: .subway)],
                location: Coordinate(lat: 52.52, lon: 13.405),
                distance: 120
            ),
            NearbyStop(
                id: "stop-2",
                name: "Market Square",
                type: .tram,
                lines: [LineInfo(name: "M1", direction: "Rosenthal", type: .tram)],
                location: Coordinate(lat: 52.521, lon: 13.406),
                distance: 85
            )
        ]

        await viewModel.loadStops(near: Coordinate(lat: 52.52, lon: 13.405)) { _, _ in stops }

        XCTAssertEqual(viewModel.stopColors["stop-1"], StopPalette.color(at: 0))
        XCTAssertEqual(viewModel.stopColors["stop-2"], StopPalette.color(at: 1))
    }

    @MainActor
    func testDepartureDetailViewModelKeepsDeparturesWhenRouteFails() async {
        let viewModel = DepartureDetailViewModel()
        let expectedDepartures = [
            Departure(
                time: "2026-02-17T14:45:00+02:00",
                realTime: true,
                delay: 120,
                line: LineInfo(name: "U2", direction: "Pankow", type: .subway)
            )
        ]

        await viewModel.load(
            stopId: "stop-1",
            from: Coordinate(lat: 52.52, lon: 13.405),
            to: Coordinate(lat: 52.521, lon: 13.406),
            fetchDepartures: { _ in expectedDepartures },
            fetchDirections: { _, _ in throw APIError.requestFailed }
        )

        XCTAssertEqual(viewModel.departures.count, 1)
        XCTAssertNil(viewModel.walkingRoute)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testDepartureDetailViewModelShowsDeparturesBeforeSlowRouteFinishes() async {
        let viewModel = DepartureDetailViewModel()
        let expectedDepartures = [
            Departure(time: "2026-02-17T14:45:00+02:00", realTime: true, delay: nil)
        ]
        let route = WalkingRoute(
            geometry: GeoJSONLineString(
                type: "LineString",
                coordinates: [[13.405, 52.52], [13.406, 52.521]]
            ),
            duration: 120,
            distance: 180
        )

        let loadTask = Task { @MainActor in
            await viewModel.load(
                stopId: "stop-1",
                from: Coordinate(lat: 52.52, lon: 13.405),
                to: Coordinate(lat: 52.521, lon: 13.406),
                fetchDepartures: { _ in expectedDepartures },
                fetchDirections: { _, _ in
                    try await Task.sleep(nanoseconds: 200_000_000)
                    return route
                }
            )
        }

        await Task.yield()

        XCTAssertEqual(viewModel.departures.count, 1)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.walkingRoute)

        await loadTask.value
        XCTAssertNotNil(viewModel.walkingRoute)
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
