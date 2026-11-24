import UIKit
import XCTest
@testable import Departs

final class DepartsTests: XCTestCase {
    @MainActor func testAppSupportsOneWindow() {
        XCTAssertFalse(UIApplication.shared.supportsMultipleScenes)
    }

    func testMapPanesFollowWindowSize() {
        func layout(_ width: CGFloat, _ height: CGFloat, pad: Bool = true) -> TransitLayout {
            let size = CGSize(width: width, height: height)
            return TransitLayout(window: size, available: size, isPad: pad)
        }
        let tall = TransitLayout(window: CGSize(width: 800, height: 820),
                                 available: CGSize(width: 800, height: 768), isPad: true)
        XCTAssertFalse(tall.sideBySide)
        XCTAssertEqual(tall.stackedMapHeight, 384)
        let narrow = TransitLayout(window: CGSize(width: 375, height: 1376),
                                   available: CGSize(width: 375, height: 1324), isPad: true)
        XCTAssertFalse(narrow.sideBySide)
        XCTAssertEqual(narrow.stackedMapHeight, 375)
        XCTAssertFalse(layout(1024, 1366).sideBySide)
        XCTAssertEqual(layout(1024, 1366).stackedMapHeight, 683)
        XCTAssertFalse(layout(820, 820).sideBySide)
        XCTAssertFalse(layout(767, 440).sideBySide)
        XCTAssertEqual(layout(650, 400).stackedMapHeight, 200)
        XCTAssertTrue(layout(768, 500).sideBySide)
        XCTAssertEqual(layout(768, 500).mapWidth, 384)
        XCTAssertFalse(layout(852, 393, pad: false).sideBySide)
        XCTAssertEqual(layout(402, 874, pad: false).stackedMapHeight, 402)
    }

    func testDeviceFamiliesOrientationsAndLocalNetworking() throws {
        // Bundle.infoDictionary resolves device-specific keys for the running host.
        // Read the packaged plist so each simulator verifies both device families.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Info", withExtension: "plist"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let info = try XCTUnwrap(plist as? [String: Any])
        XCTAssertEqual(info["UIDeviceFamily"] as? [Int], [1, 2])
        XCTAssertEqual(info["UISupportedInterfaceOrientations"] as? [String], ["UIInterfaceOrientationPortrait"])
        XCTAssertEqual(Set(try XCTUnwrap(info["UISupportedInterfaceOrientations~ipad"] as? [String])),
                       ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                        "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"])
        XCTAssertEqual(info["MinimumOSVersion"] as? String, "26.0")
        let transport = info["NSAppTransportSecurity"] as? [String: Any]
        #if DEBUG
        XCTAssertEqual(transport?["NSAllowsLocalNetworking"] as? Bool, true)
        #else
        XCTAssertNil(transport?["NSAllowsLocalNetworking"])
        #endif
    }


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

    func testNearbyStopCreatesSelectionForEveryLineDirection() {
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

        XCTAssertEqual(stop.lineSelections.count, 4)
        XCTAssertEqual(stop.lineSelections.map(\.line.name), ["17", "17", "18", "19"])
        XCTAssertEqual(stop.lineSelections.map(\.line.direction), ["Alvik", "Skarpnäck", "Farsta strand", "Hagsätra"])
    }

    func testStopLineSelectionHasStableUniqueIdsForRepeatedLineNames() {
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

        let ids = stop.lineSelections.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
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

    func testDepartureURLIncludesSelectedLineAndDirection() throws {
        let url = try APIService.departuresURL(
            stopId: "stop/1?platform=A&B",
            line: LineInfo(name: "17", direction: "Hässelby strand", type: .subway)
        )

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        XCTAssertEqual(queryItems?.first { $0.name == "stopId" }?.value, "stop/1?platform=A&B")
        XCTAssertEqual(queryItems?.first { $0.name == "lineName" }?.value, "17")
        XCTAssertEqual(queryItems?.first { $0.name == "direction" }?.value, "Hässelby strand")
    }

    func testDepartureURLEncodesAPlusSoServersDoNotReadASpace() throws {
        let url = try APIService.departuresURL(
            stopId: "49031_783",
            line: LineInfo(name: "U2", direction: "S+U Pankow", type: .subway)
        )

        XCTAssertEqual(url.absoluteString,
                       "https://departs.vercel.app/api/departures?stopId=49031_783&lineName=U2&direction=S%2BU%20Pankow")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "direction" }?.value,
                       "S+U Pankow")
    }

    func testEveryRequestURLEncodesPlusSigns() throws {
        let urls = [
            try APIService.departuresURL(stopId: "a+b", line: LineInfo(name: "S+1", direction: "S+U X", type: .rail)),
            try APIService.batchDeparturesURL(stopIDs: ["a+b", "c"]),
            try APIService.nearbyStopsURL(lat: 52.5219, lon: 13.4132),
            try APIService.directionsURL(from: Coordinate(lat: 52.5219, lon: 13.4132), to: Coordinate(lat: 52.52, lon: 13.41)),
        ]
        for url in urls {
            XCTAssertFalse(url.absoluteString.contains("+"), url.absoluteString)
        }
        XCTAssertEqual(urls[0].query(percentEncoded: true), "stopId=a%2Bb&lineName=S%2B1&direction=S%2BU%20X")
        XCTAssertEqual(urls[1].query(percentEncoded: true), "stopIds=a%2Bb,c")
    }

    // MARK: - StopPalette

    func testDistancesUseTheLocalesMeasurementSystem() {
        XCTAssertEqual(TransitFormat.distance(400, locale: Locale(identifier: "de_DE")), "400 m")
        XCTAssertEqual(TransitFormat.distance(400, locale: Locale(identifier: "en_US")), "1,300 ft")
        XCTAssertEqual(TransitFormat.distance(400, locale: Locale(identifier: "en_GB")), "450 yd")
        XCTAssertEqual(TransitFormat.minutes(3, locale: Locale(identifier: "de_DE")), "3 Min.")
        XCTAssertEqual(TransitFormat.minutes(3, locale: Locale(identifier: "en_US")), "3 min")
    }

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
