import XCTest
import CoreLocation
import Network

/// Exercises the real screens and URLSession client with a local, controllable HTTP API.
/// No provider credentials, production requests, or test data are compiled into the release app.
final class DepartsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var server: TransitFixtureServer!

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = try TransitFixtureServer()
        let ready = expectation(description: "Fixture server ready")
        server.start { ready.fulfill() }
        wait(for: [ready], timeout: 5)
        app = XCUIApplication()
        app.launchEnvironment["DEPARTS_API_BASE_URL"] = server.baseURL
        app.launchEnvironment["DEPARTS_DEFAULTS_SUITE"] = "departs-ui-\(UUID().uuidString)"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.20134, longitude: 16.34941))
        app.resetAuthorizationStatus(for: .location)
    }

    override func tearDownWithError() throws {
        app.terminate()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        if maps.state != .notRunning { maps.terminate() }
        dismissMapsPrompt()
        server.stop()
        XCUIDevice.shared.location = nil
    }

    func testFirstScreenPinsRelaunchAndDirectEntry() {
        launchAndAllowLocation()
        let option = app.buttons["departure-option"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Live'")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.maps.firstMatch.exists, "A map must not delay the opening answer")
        let screen = app.frame
        let visible = app.buttons.matching(identifier: "departure-option").allElementsBoundByIndex.filter { screen.contains($0.frame) }
        print("REQUESTS opening=\(server.departureCount)")
        XCTAssertLessThanOrEqual(server.departureCount, 3)
        print("DENSITY first=\(option.frame.minY) visible=\(visible.count)")
        XCTAssertLessThanOrEqual(option.frame.minY, screen.height <= 667 ? 130 : 170)
        XCTAssertGreaterThanOrEqual(visible.count, screen.height <= 667 ? 5 : 6)
        capture("Nearby departures")
        option.swipeLeft()
        app.buttons["pin-route"].firstMatch.tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["departure-option"].firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["unpin-route"].firstMatch.exists)

        let id = ["fixture-stop", "tram", "49", "Hütteldorf"].map { "\($0.utf8.count):\($0)" }.joined()
        var link = URLComponents(string: "departs://pin")!
        link.queryItems = [URLQueryItem(name: "id", value: id)]
        app.open(link.url!)
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Next departures"].exists)
        capture("Pinned departure detail")
    }

    func testCountdownKeepsVisibleRouteOrder() {
        launchAndAllowLocation()
        let rows = app.buttons.matching(identifier: "departure-option")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 12))
        let before = rows.allElementsBoundByIndex.compactMap { $0.value as? String }
        let tick = expectation(description: "One countdown tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { tick.fulfill() }
        wait(for: [tick], timeout: 20)
        XCTAssertEqual(rows.allElementsBoundByIndex.compactMap { $0.value as? String }, before)
    }

    func testFailedRefreshKeepsSavedTimesAndRecovers() {
        launchAndAllowLocation()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Live'")).firstMatch.waitForExistence(timeout: 12))
        app.buttons["departure-option"].firstMatch.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        server.setOffline(true)
        app.buttons["Refresh departures"].tap()
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Saved information'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Leave in' OR label == 'Leave now'")).firstMatch.exists)
        capture("Saved departures after failed refresh")
        server.setOffline(false)
        app.buttons["Refresh departures"].tap()
        let updated = app.staticTexts.matching(NSPredicate(format: "identifier == 'board-status' AND label BEGINSWITH 'Updated'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
    }

    func testWiderSearchAndAreaSearchStayAvailable() {
        launchAndAllowLocation()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 12))
        for _ in 0..<5 {
            if app.buttons["search-farther"].exists && app.buttons["search-farther"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["search-farther"].tap()
        let requested = expectation(for: NSPredicate { _, _ in self.server.radii.contains(800) }, evaluatedWith: nil)
        wait(for: [requested], timeout: 5)
        app.buttons["choose-area"].tap()
        XCTAssertTrue(app.textFields["area-query"].waitForExistence(timeout: 3))
        capture("Choose an area")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.exists)
        app.buttons["departure-option"].firstMatch.tap()
        app.buttons["walking-directions"].tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Maps").wait(for: .runningForeground, timeout: 5))
    }

    func testDeniedLocationOffersSearchAndLargeTextRemainsUsable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Don’t Allow"].tap()
        XCTAssertTrue(app.staticTexts["location-status"].waitForExistence(timeout: 5))
        app.buttons["choose-area"].tap()
        XCTAssertTrue(app.textFields["area-query"].waitForExistence(timeout: 3))
        capture("Location denied with accessibility text")
    }

    func testForegroundRefreshKeepsCachedAnswerWhenOffline() {
        launchAndAllowLocation()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Live'")).firstMatch.waitForExistence(timeout: 12), app.debugDescription)
        XCUIDevice.shared.press(.home)
        server.setOffline(true)
        app.activate()
        let saved = app.staticTexts.matching(NSPredicate(format: "identifier == 'board-status' AND label CONTAINS 'Saved'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.exists)
        capture("Offline on foreground return")
    }

    func testLargeTextKeepsDirectionAndWalkingActionAccessible() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchAndAllowLocation()
        let option = app.buttons["departure-option"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 12))
        capture("Nearby at accessibility text size")
        option.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["walking-directions"].isHittable)
        capture("Detail at accessibility text size")
    }

    private func launchAndAllowLocation() {
        dismissMapsPrompt()
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            alert.buttons["Allow While Using App"].tap()
        }
    }

    private func dismissMapsPrompt() {
        let prompt = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.matching(NSPredicate(format: "label CONTAINS 'Maps'")).firstMatch
        if prompt.exists, prompt.buttons["Don’t Allow"].exists { prompt.buttons["Don’t Allow"].tap() }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class TransitFixtureServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "departs.ui-fixtures")
    private var offline = false
    private var requestedRadii: [Int] = []
    private var departureRequests = 0
    var departureCount: Int { queue.sync { departureRequests } }
    var baseURL: String { "http://127.0.0.1:\(listener.port!.rawValue)" }
    var radii: [Int] { queue.sync { requestedRadii } }

    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { state in if case .ready = state { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }
    func setOffline(_ value: Bool) { queue.sync { offline = value } }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var bytes = buffer
            bytes.append(data ?? Data())
            guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, buffer: bytes) }
                return
            }
            let path = request.components(separatedBy: " ").dropFirst().first ?? "/"
            let url = URLComponents(string: "http://localhost\(path)")!
            let payload = self.response(to: url)
            let body = try! JSONSerialization.data(withJSONObject: payload)
            let status = self.offline ? "503 Service Unavailable" : "200 OK"
            var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func response(to url: URLComponents) -> Any {
        if offline { return ["error": "Offline fixture"] }
        let lines: [[String: Any]] = (0..<8).map { index in
            ["name": "\(49 + index)", "direction": index == 0 ? "Hütteldorf" : "Destination \(index)", "type": "tram"]
        }
        let line = lines.first { $0["name"] as? String == url.queryItems?.first(where: { $0.name == "lineName" })?.value } ?? lines[0]
        switch url.path {
        case "/api/stops/nearby":
            requestedRadii.append(Int(url.queryItems?.first { $0.name == "radius" }?.value ?? "0") ?? 0)
            return [["id": "fixture-stop", "name": "Volkstheater", "type": "tram", "location": ["lat": 48.204, "lon": 16.357], "distance": 280, "lines": lines]]
        case "/api/departures":
            departureRequests += 1
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(identifier: "Europe/Vienna")
            func board(_ service: [String: Any]) -> [[String: Any]] {
                [7, 12].enumerated().map { index, minutes in
                    ["time": formatter.string(from: Date().addingTimeInterval(Double(minutes * 60))), "realTime": index == 0, "line": service]
                }
            }
            if url.queryItems?.contains(where: { $0.name == "groupBy" && $0.value == "line" }) == true {
                return ["groups": lines.map { ["line": $0, "departures": board($0)] }]
            }
            return board(line)
        case "/api/directions":
            return ["duration": 180, "distance": 280, "geometry": ["type": "LineString", "coordinates": [[16.34941, 48.20134], [16.357, 48.204]]]]
        default: return ["error": "Unexpected fixture URL"]
        }
    }
}
