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
        app.launchEnvironment["DEPARTS_TEST_PLACE_SEARCH"] = "1"
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
        assertTarget(option)
        assertTarget(app.buttons["pin-hint"])
        capture("Nearby departures")
        option.swipeLeft()
        assertTarget(app.buttons["pin-route"].firstMatch)
        app.buttons["pin-route"].firstMatch.tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["departure-option"].firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["unpin-route"].firstMatch.exists)
        assertTarget(app.buttons["unpin-route"].firstMatch)

        let id = ["fixture-stop", "tram", "49", "Hütteldorf"].map { "\($0.utf8.count):\($0)" }.joined()
        var link = URLComponents(string: "departs://pin")!
        link.queryItems = [URLQueryItem(name: "id", value: id)]
        app.open(link.url!)
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Next departures"].exists)
        XCTAssertGreaterThan(app.buttons["walking-directions"].frame.width, 140, "The toolbar must visibly show its title, not only the icon")
        capture("Pinned departure detail")
    }

    func testCountdownKeepsVisibleRouteOrder() {
        launchAndAllowLocation()
        let rows = app.buttons.matching(identifier: "departure-option")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Live'")).firstMatch.waitForExistence(timeout: 8))
        let before = routeOrder(rows)
        XCTAssertGreaterThanOrEqual(before.count, 6)
        XCTAssertFalse(before.contains { $0.contains("55 toward") || $0.contains("56 toward") }, "Future and idle lines must be collapsed")
        let tick = expectation(description: "One countdown tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { tick.fulfill() }
        wait(for: [tick], timeout: 20)
        XCTAssertEqual(routeOrder(rows), before)
        XCTAssertTrue(rows.allElementsBoundByIndex.allSatisfy { ($0.value as? String ?? "").isEmpty }, "Opaque identities must not be spoken as accessibility values")
    }

    func testFutureRowsAndChangedBoardsUseTheHorizon() {
        launchAndAllowLocation()
        let rows = app.buttons.matching(identifier: "departure-option")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Live'")).firstMatch.waitForExistence(timeout: 12))
        let disclosure = app.buttons["2 lines with nothing soon"].firstMatch
        for _ in 0..<3 where !disclosure.isHittable { app.swipeUp() }
        assertTarget(disclosure)
        disclosure.tap()
        let future = app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Tram 55 toward'")).firstMatch
        XCTAssertTrue(future.waitForExistence(timeout: 4))
        XCTAssertFalse(future.label.contains("Leave"))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label BEGINSWITH 'Nothing soon. Tram 56'")).firstMatch.exists)
        capture("Expanded future and idle lines")
        disclosure.tap()
        for _ in 0..<5 where rows.firstMatch.frame.minY < 120 { app.swipeDown() }
        server.setChangedServices()
        let beforeRefresh = server.radii.count
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.5)
        let refreshed = expectation(for: NSPredicate { _, _ in self.server.radii.count > beforeRefresh }, evaluatedWith: nil)
        wait(for: [refreshed], timeout: 5)
        let gained = app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Tram 56 toward'")).firstMatch
        let repartitioned = expectation(for: NSPredicate(format: "label CONTAINS 'Tram 50 toward'"), evaluatedWith: rows.firstMatch)
        wait(for: [repartitioned], timeout: 8)
        for _ in 0..<4 where !gained.exists { app.swipeUp() }
        XCTAssertTrue(gained.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Tram 49 toward'")).firstMatch.exists)
        capture("Changed boards after refresh")
    }

    func testBoardArrivingDuringScrollKeepsProviderOrder() {
        server.holdSecondBoard()
        launchAndAllowLocation()
        let rows = app.buttons.matching(identifier: "departure-option")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 12))
        let held = expectation(for: NSPredicate { _, _ in self.server.heldCount > 0 }, evaluatedWith: nil)
        wait(for: [held], timeout: 5)
        let firstSection = Array(routeOrder(rows).prefix(6))
        let fixture = server!
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { fixture.releaseHeldBoards() }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            .press(forDuration: 0.2, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertEqual(server.heldCount, 0)
        XCTAssertEqual(Array(routeOrder(rows).prefix(6)), firstSection)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'from Second stop'")).firstMatch.exists)
        capture("Board delivered during scroll")
    }

    func testScrollingLoadsVisibleSectionsAndRefreshesOnlyTheViewport() {
        server.setExtendedStops()
        launchAndAllowLocation()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 12))
        let last = app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'from Extra stop 7'")).firstMatch
        for _ in 0..<14 {
            if last.exists && last.isHittable { break }
            app.swipeUp()
        }
        let loaded = app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'from Extra stop 7' AND (label CONTAINS 'Live' OR label CONTAINS 'Scheduled')")).firstMatch
        print("REQUESTS scrolled stops=\(server.requestedStops)")
        let didLoad = loaded.waitForExistence(timeout: 8)
        print("LAST ROW \(last.exists ? last.label : "missing")")
        capture("Last stop visibility check")
        XCTAssertTrue(didLoad, "Visible rows must demand stops beyond the three opening boards")
        server.clearRequestedStops()
        // A stop loaded late during the scroll may still be inside the 25-second
        // throttle on the next 30-second tick. Observe its eligible refresh.
        let refresh = expectation(for: NSPredicate { _, _ in
            self.server.requestedStops.contains("extra-7")
        }, evaluatedWith: nil)
        wait(for: [refresh], timeout: 65)
        let refreshed = Set(server.requestedStops)
        XCTAssertTrue(refreshed.contains("extra-7"))
        XCTAssertFalse(refreshed.contains("fixture-stop"), "An offscreen section must leave the refresh set")
        XCTAssertFalse(refreshed.contains("second-stop"))
        print("REQUESTS viewport after scrolling=\(server.requestedStops.count), stops=\(refreshed.sorted())")
        capture("Visible sections after scrolling")
    }

    func testLegacyServerLoadsBoardsWithoutGroupedSupport() {
        server.setLegacy()
        launchAndAllowLocation()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Live'")).firstMatch.waitForExistence(timeout: 12))
        XCTAssertEqual(server.individualCount, 10)
        XCTAssertLessThanOrEqual(server.departureCount, 12)
        print("REQUESTS legacy opening=\(server.departureCount), per-line=\(server.individualCount)")
        capture("Legacy server fallback")
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
        XCTAssertEqual(app.staticTexts["departure-advice-title"].label, "Refresh before you leave",
                       "The selected board must not give leave advice after its refresh fails")
        capture("Saved departures after failed refresh")
        server.setOffline(false)
        XCTAssertTrue(app.buttons["refresh-advice"].exists)
        app.buttons["refresh-advice"].tap()
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
        assertTarget(app.buttons["search-farther"])
        app.buttons["search-farther"].tap()
        let requested = expectation(for: NSPredicate { _, _ in self.server.radii.contains(800) }, evaluatedWith: nil)
        wait(for: [requested], timeout: 5)
        app.buttons["choose-area"].tap()
        XCTAssertTrue(app.textFields["area-query"].waitForExistence(timeout: 3))
        capture("Choose an area")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.exists)
        let visible = app.buttons.matching(identifier: "departure-option").allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.minY > app.navigationBars.firstMatch.frame.maxY && $0.frame.maxY < app.frame.maxY
        }
        XCTAssertNotNil(visible)
        visible!.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        app.buttons["walking-directions"].tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Maps").wait(for: .runningForeground, timeout: 5))
    }

    func testRouteMapOpensInVisibleSheetAndStopNameAppearsOnce() {
        launchAndAllowLocation()
        let option = app.buttons["departure-option"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 12))
        option.tap()
        XCTAssertTrue(app.buttons["show-route-map"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'Volkstheater'")).count, 1)
        app.buttons["show-route-map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.maps.firstMatch.isHittable)
        capture("Route map sheet")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["departure-too-tight"].exists)
        let other = app.buttons["other-line"].firstMatch
        for _ in 0..<6 {
            if other.isHittable && other.frame.maxY < app.buttons["walking-directions"].frame.minY { break }
            app.swipeUp()
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier == 'other-line' AND label CONTAINS 'Tram 55 toward'")).firstMatch.exists)
        capture("Other lines at this stop")
        other.tap()
        XCTAssertTrue(app.navigationBars["50 Destination 1"].waitForExistence(timeout: 5))
    }

    func testStopMapSelectionReturnsToList() {
        server.setMergedPlatforms()
        launchAndAllowLocation()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 12))
        app.buttons["Show nearby map"].tap()
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'stop-map-pin' AND label BEGINSWITH 'Volkstheater,'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "stop-map-pin").count, 2, "Three provider platforms form two physical stops")
        assertTarget(pin)
        let chosenLabel = pin.label
        pin.tap()
        XCTAssertTrue(app.buttons["Show in list"].waitForExistence(timeout: 5))
        assertTarget(app.buttons["Show in list"])
        capture("Selected stop map")
        let chosen = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'stop-map-pin' AND label == %@", chosenLabel)).firstMatch
        XCTAssertTrue(chosen.isSelected, app.debugDescription)
        app.buttons["Show in list"].tap()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.maps.firstMatch.exists)
    }

    func testChosenPlaceAppearsInRecentsAfterRelaunch() {
        launchAndAllowLocation()
        app.buttons["choose-area"].tap()
        let query = app.textFields["area-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("Volkstheater")
        let result = app.buttons["area-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 12))
        app.terminate()
        app.launch()
        app.buttons["choose-area"].tap()
        XCTAssertTrue(app.buttons["recent-area"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Current location"].exists)
        XCTAssertLessThan(app.buttons["Current location"].frame.maxY, app.staticTexts["Recent places"].frame.minY)
        capture("Recent places")
        app.buttons["recent-area"].firstMatch.tap()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 5))
    }

    func testDeniedLocationOffersSearchAndLargeTextRemainsUsable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Don’t Allow"].tap()
        XCTAssertTrue(app.staticTexts["location-status"].waitForExistence(timeout: 5))
        capture("Location denied with accessibility text")
        assertTarget(app.buttons["Open Settings"])
        app.buttons["choose-area"].tap()
        XCTAssertTrue(app.textFields["area-query"].waitForExistence(timeout: 3))
        capture("Search after location denied")
    }

    func testForegroundRefreshKeepsCachedAnswerWhenOffline() {
        launchAndAllowLocation()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Live'")).firstMatch.waitForExistence(timeout: 12), app.debugDescription)
        server.setOffline(true)
        XCUIDevice.shared.press(.home)
        let interval = expectation(description: "Non-forced refresh interval elapses")
        DispatchQueue.main.asyncAfter(deadline: .now() + 26) { interval.fulfill() }
        wait(for: [interval], timeout: 30)
        app.activate()
        let saved = app.staticTexts.matching(NSPredicate(format: "identifier == 'board-status' AND label CONTAINS 'Saved'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        assertTarget(app.buttons["refresh-list"])
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.exists)
        capture("Offline on foreground return")
    }

    func testLargeTextKeepsDirectionAndWalkingActionAccessible() {
        server.setLongDirection()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launchAndAllowLocation()
        let option = app.buttons["departure-option"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 12))
        capture("Nearby at accessibility text size")
        option.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        capture("Detail at accessibility text size")
        XCTAssertGreaterThan(app.buttons["walking-directions"].frame.width, 140, "The toolbar title remains visible at accessibility text sizes")
        let direction = app.staticTexts["detail-direction"]
        XCTAssertEqual(direction.label, "Wien Kaiserebersdorf, Zinnergasse")
        XCTAssertGreaterThan(direction.frame.height, 80, "The full headsign wraps and scales with accessibility text")
        XCTAssertTrue(app.frame.contains(direction.frame))
        for _ in 0..<8 {
            if app.buttons["show-route-map"].isHittable && app.buttons["show-route-map"].frame.maxY < app.buttons["walking-directions"].frame.minY { break }
            app.swipeUp()
        }
        assertTarget(app.buttons["show-route-map"])
        app.buttons["show-route-map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.maps.firstMatch.isHittable)
        capture("Route map at accessibility text size")
        app.buttons["Done"].tap()
        // The native toolbar's accessibility hit-point query is unreliable on
        // iOS 27. Verify the actual tap and Apple Maps handoff at its visible center.
        app.buttons["walking-directions"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Maps").wait(for: .runningForeground, timeout: 5))
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

    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, file: file, line: line)
        print("TARGET \(element.identifier) \(element.frame.width)×\(element.frame.height)")
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.001, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.001, 44, file: file, line: line)
    }

    private func routeOrder(_ rows: XCUIElementQuery) -> [String] {
        rows.allElementsBoundByIndex.compactMap { row in
            guard let range = row.label.range(of: "(Tram|Bus|Subway|Train) .* toward .* from [^.]+", options: .regularExpression) else { return nil }
            return String(row.label[range])
        }
    }
}

private final class TransitFixtureServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "departs.ui-fixtures")
    private var offline = false
    private var requestedRadii: [Int] = []
    private var departureRequests = 0
    private var firstBoardAt: Date?
    private var changedServices = false
    private var legacy = false
    private var holdingSecond = false
    private var heldResponses: [() -> Void] = []
    private var individualRequests = 0
    private var extendedStops = false
    private var mergedPlatforms = false
    private var longDirection = false
    private var requestedStopIDs: [String] = []
    var departureCount: Int { queue.sync { departureRequests } }
    var individualCount: Int { queue.sync { individualRequests } }
    var heldCount: Int { queue.sync { heldResponses.count } }
    var requestedStops: [String] { queue.sync { requestedStopIDs } }
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
    func setChangedServices() { queue.sync { changedServices = true } }
    func setLegacy() { queue.sync { legacy = true } }
    func setExtendedStops() { queue.sync { extendedStops = true } }
    func setMergedPlatforms() { queue.sync { mergedPlatforms = true } }
    func setLongDirection() { queue.sync { longDirection = true } }
    func clearRequestedStops() { queue.sync { requestedStopIDs = [] } }
    func holdSecondBoard() { queue.sync { holdingSecond = true } }
    func releaseHeldBoards() { queue.sync {
        holdingSecond = false
        let responses = heldResponses
        heldResponses = []
        responses.forEach { $0() }
    } }

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
            let send = { connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() }) }
            if self.holdingSecond, url.path == "/api/departures", url.queryItems?.first(where: { $0.name == "stopId" })?.value == "second-stop" {
                self.heldResponses.append(send)
            } else { send() }
        }
    }

    private func response(to url: URLComponents) -> Any {
        if offline { return ["error": "Offline fixture"] }
        let lines: [[String: Any]] = (0..<8).map { index in
            ["name": "\(49 + index)", "direction": index == 0 ? (longDirection ? "Wien Kaiserebersdorf, Zinnergasse" : "Hütteldorf") : "Destination \(index)", "type": "tram"]
        }
        let secondLines: [[String: Any]] = [["name": "77", "direction": "Station", "type": "tram"], ["name": "78", "direction": "Park", "type": "tram"]]
        let line = (lines + secondLines).first { $0["name"] as? String == url.queryItems?.first(where: { $0.name == "lineName" })?.value } ?? lines[0]
        switch url.path {
        case "/test/places":
            return [["name": "Volkstheater", "coordinate": ["lat": 48.204, "lon": 16.357], "source": "chosen"]]
        case "/api/stops/nearby":
            requestedRadii.append(Int(url.queryItems?.first { $0.name == "radius" }?.value ?? "0") ?? 0)
            var stops: [[String: Any]] = [["id": "fixture-stop", "name": "Volkstheater", "type": "tram", "location": ["lat": 48.203, "lon": 16.3515], "distance": 280, "lines": lines],
                    ["id": "second-stop", "name": "Second stop", "type": "tram", "location": ["lat": 48.204, "lon": 16.352], "distance": 360,
                     "lines": secondLines]]
            if extendedStops {
                stops += (0..<8).map { ["id": "extra-\($0)", "name": "Extra stop \($0)", "type": "tram", "location": ["lat": 48.204, "lon": 16.352], "distance": 380, "lines": secondLines] }
            }
            if mergedPlatforms {
                stops.append(["id": "other-platform", "name": "Volkstheater", "type": "tram",
                              "location": ["lat": 48.20305, "lon": 16.35155], "distance": 285, "lines": secondLines])
            }
            return stops
        case "/api/departures":
            departureRequests += 1
            requestedStopIDs.append(url.queryItems?.first(where: { $0.name == "stopId" })?.value ?? "")
            if firstBoardAt == nil { firstBoardAt = Date() }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(identifier: "Europe/Vienna")
            func board(_ service: [String: Any]) -> [[String: Any]] {
                let minutes: [Double]
                switch service["name"] as? String {
                case "49": minutes = changedServices ? [] : [3, 13]
                case "50": minutes = [8, 14]
                case "51": minutes = [14, 20]
                case "52": minutes = [25, 32]
                case "53": minutes = [45, 55]
                case "54": minutes = [58, 65]
                case "55": minutes = [60.1, 166]
                case "56": minutes = changedServices ? [4, 14] : []
                case "77": minutes = holdingSecond ? [] : [2, 9]
                case "78": minutes = holdingSecond ? [134] : [2, 9]
                default: minutes = [2, 9]
                }
                return minutes.enumerated().map { index, minutes in
                    ["time": formatter.string(from: firstBoardAt!.addingTimeInterval(minutes * 60)), "realTime": index == 0, "line": service]
                }
            }
            if url.queryItems?.contains(where: { $0.name == "groupBy" && $0.value == "line" }) == true {
                if legacy { return board(line) }
                let requestedLines: [[String: Any]] = url.queryItems?.first(where: { $0.name == "stopId" })?.value == "fixture-stop" ? lines : secondLines
                return ["groups": requestedLines.map { ["line": $0, "departures": board($0)] }, "complete": true]
            }
            individualRequests += 1
            return board(line)
        case "/api/directions":
            let from = url.queryItems!.first { $0.name == "from" }!.value!.split(separator: ",").map { Double($0)! }
            let to = url.queryItems!.first { $0.name == "to" }!.value!.split(separator: ",").map { Double($0)! }
            return ["duration": 180, "distance": 280, "geometry": ["type": "LineString", "coordinates": [[from[1], from[0]], [to[1], to[0]]]]]
        default: return ["error": "Unexpected fixture URL"]
        }
    }
}
