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
        XCTAssertEqual(url.host, "api.departs.now")
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
                       "https://api.departs.now/api/departures?stopId=49031_783&lineName=U2&direction=S%2BU%20Pankow")
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

final class APITransportTests: XCTestCase {
    private let origin = Coordinate(lat: 48.20134, lon: 16.34941)
    private let platform = Coordinate(lat: 48.2015, lon: 16.3491)
    private let walkJSON = """
        {"duration":120,"distance":140,"geometry":{"type":"LineString","coordinates":[[16.34941,48.20134],[16.3491,48.2015]]}}
        """

    func testHosted500And502UseTheSameFailureForEveryEndpoint() async throws {
        let calls: [(APIService) async throws -> Void] = [
            { _ = try await $0.fetchNearbyStops(lat: self.origin.lat, lon: self.origin.lon) },
            { _ = try await $0.fetchDepartureBoards(stopIDs: ["fixture"]) },
            { _ = try await $0.fetchDepartures(stopId: "fixture", line: .init(name: "U2", direction: "Pankow", type: .subway)) },
            { _ = try await $0.fetchDirections(from: self.origin, to: self.platform) },
        ]
        let json = #"{"error":"Provider failed"}"#
        let cases: [(status: Int, contentType: String, body: String)] = [
            (500, "application/json", json),
            (502, "application/json", json),
            (500, "text/html", "<html>Internal Server Error</html>"),
        ]
        for response in cases {
            let stub = APIResponseStub { _, _ in
                .init(status: response.status, headers: ["Content-Type": response.contentType], body: response.body)
            }
            let label = "HTTP \(response.status) with \(response.contentType)"
            let service = stub.service(waitForRetry: { _ in XCTFail("Unexpected retry for \(label)") })
            for call in calls {
                do {
                    try await call(service)
                    XCTFail("Expected \(label) to fail")
                } catch APIError.requestFailed {
                    // The store receives the same error from both hosts.
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(stub.requestCount, 4)
        }
    }

    func testRateLimitRetriesOnceWithHeaderOrDefaultDelayAndCanRecover() async throws {
        let date = Date(timeIntervalSince1970: 1_706_017_680)
        let cases: [(String?, TimeInterval)] = [
            (nil, 2), ("1", 1), ("60", 5), ("-3", 2), ("not a date or number", 2),
            ("Tue, 23 Jan 2024 13:47:57 GMT", 0),
            ("Tue, 23 Jan 2024 13:48:03 GMT", 3),
            ("Tue, 23 Jan 2024 13:49:00 GMT", 5),
        ]
        for (header, expectedDelay) in cases {
            let stub = APIResponseStub { _, index in
                if index == 1 { return .init(status: 429, headers: header.map { ["Retry-After": $0] } ?? [:], body: "<html>Busy</html>") }
                return .init(status: 200, body: "[]")
            }
            let label = "Retry-After: \(header ?? "(missing)")"
            let waited = expectation(description: label)
            let service = stub.service(now: { date }) { delay in
                XCTAssertEqual(delay, expectedDelay, label)
                waited.fulfill()
            }
            let stops = try await service.fetchNearbyStops(lat: origin.lat, lon: origin.lon)
            await fulfillment(of: [waited], timeout: 1)
            XCTAssertTrue(stops.isEmpty)
            XCTAssertEqual(stub.requestCount, 2)
        }
    }

    func testRepeatedHTMLRateLimitIsATemporaryFailure() async throws {
        let stub = APIResponseStub { _, _ in .init(status: 429, body: "<html>Busy</html>") }
        let service = stub.service(waitForRetry: { delay in XCTAssertEqual(delay, 2) })
        do {
            _ = try await service.fetchDepartureBoards(stopIDs: ["fixture"])
            XCTFail("Expected a temporary failure after one retry")
        } catch APIError.requestFailed {
            XCTAssertEqual(stub.requestCount, 2)
        }
    }

    func testNearbyStopCacheWorksWithoutHTTPCachingFor24Hours() async throws {
        let clock = APITestClock()
        let stub = APIResponseStub { _, index in
            .init(status: 200, headers: index == 1 ? [:] : ["Cache-Control": "private, no-store"], body: """
                [{"id":"stop-\(index)","name":"Fixture","type":"bus","lines":[],"location":{"lat":48.2015,"lon":16.3491}}]
                """)
        }
        let service = stub.service(now: { clock.now })
        let first = try await service.fetchNearbyStops(lat: origin.lat, lon: origin.lon)
        clock.advance(by: 86_399)
        let relaunched = stub.service(now: { clock.now })
        let stillFresh = try await relaunched.fetchNearbyStops(lat: origin.lat, lon: origin.lon)
        XCTAssertEqual(stillFresh.first?.id, first.first?.id)
        XCTAssertEqual(stub.requestCount, 1)
        clock.advance(by: 1)
        let expired = try await relaunched.fetchNearbyStops(lat: origin.lat, lon: origin.lon)
        let spacefastCached = try await relaunched.fetchNearbyStops(lat: origin.lat, lon: origin.lon)
        let otherLocation = try await relaunched.fetchNearbyStops(lat: platform.lat, lon: platform.lon)
        XCTAssertEqual(expired.first?.id, "stop-2")
        XCTAssertEqual(spacefastCached.first?.id, "stop-2")
        XCTAssertEqual(otherLocation.first?.id, "stop-3")
        XCTAssertEqual(stub.requestCount, 3)
    }

    func testWalkCacheExpiresAfterOneHourAndDeparturesStayFresh() async throws {
        let clock = APITestClock()
        let stub = APIResponseStub { [walkJSON] request, _ in
            .init(status: 200, headers: ["Cache-Control": "private, no-store"],
                  body: request.url?.path == "/api/directions" ? walkJSON : "[]")
        }
        let service = stub.service(now: { clock.now })
        _ = try await service.fetchDirections(from: origin, to: platform)
        clock.advance(by: 3_599)
        _ = try await service.fetchDirections(from: origin, to: platform)
        XCTAssertEqual(stub.requestCount, 1)
        clock.advance(by: 1)
        _ = try await service.fetchDirections(from: origin, to: platform)
        let line = LineInfo(name: "U2", direction: "Pankow", type: .subway)
        _ = try await service.fetchDepartures(stopId: "fixture", line: line)
        _ = try await service.fetchDepartures(stopId: "fixture", line: line)
        XCTAssertEqual(stub.requestCount, 4)
    }

    func testOverlappingRequestsUseAtMostFourSlotsAndReleaseThemOnError() async {
        let stub = APIResponseStub { _, index in
            .init(status: index == 1 ? 500 : 200, body: "[]", delay: 0.15)
        }
        let service = stub.service()
        let failures = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for index in 0..<9 {
                group.addTask {
                    do {
                        _ = try await service.fetchNearbyStops(lat: 48.2, lon: Double(index))
                        return false
                    } catch {
                        return true
                    }
                }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(stub.requestCount, 9)
        XCTAssertEqual(stub.peakRequests, 4)
    }
}

private final class APITestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date()
    var now: Date { lock.withLock { date } }
    func advance(by seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

private final class APIResponseStub: @unchecked Sendable {
    struct Reply {
        let status: Int
        var headers: [String: String] = [:]
        let body: String
        var delay: TimeInterval = 0
    }

    private let lock = NSLock()
    private var count = 0
    private var active = 0
    private var peak = 0
    private let respond: (URLRequest, Int) -> Reply
    private let baseURL = URL(string: "https://\(UUID().uuidString.lowercased()).example.invalid")!
    private let session: URLSession

    init(respond: @escaping (URLRequest, Int) -> Reply) {
        self.respond = respond
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0)
        config.protocolClasses = [StubAPIURLProtocol.self]
        session = URLSession(configuration: config)
    }

    func service(now: @escaping @Sendable () -> Date = { .now },
                 waitForRetry: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in }) -> APIService {
        StubAPIURLProtocol.register(self, for: baseURL.host!)
        return APIService(session: session, baseURL: baseURL, now: now, waitForRetry: waitForRetry)
    }

    deinit {
        StubAPIURLProtocol.unregister(baseURL.host!)
        session.invalidateAndCancel()
    }

    var requestCount: Int { lock.withLock { count } }
    var peakRequests: Int { lock.withLock { peak } }

    func started(_ request: URLRequest) -> Reply {
        let index = lock.withLock {
            count += 1
            active += 1
            peak = max(peak, active)
            return count
        }
        return respond(request, index)
    }

    func finished() { lock.withLock { active -= 1 } }
}

private final class StubAPIURLProtocol: URLProtocol {
    private final class WeakStub {
        weak var value: APIResponseStub?
        init(_ value: APIResponseStub) { self.value = value }
    }

    private static let lock = NSLock()
    private static var stubs: [String: WeakStub] = [:]

    static func register(_ stub: APIResponseStub, for host: String) {
        lock.withLock { stubs[host] = WeakStub(stub) }
    }
    static func unregister(_ host: String) {
        _ = lock.withLock { stubs.removeValue(forKey: host) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              let stub = Self.lock.withLock({ Self.stubs[host]?.value }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let reply = stub.started(request)
        let complete = {
            stub.finished()
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: DispatchWorkItem(block: complete))
        } else {
            complete()
        }
    }

    override func stopLoading() {}
}
