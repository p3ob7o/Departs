import XCTest
import CoreLocation
import Network

/// Real screens and URLSession, using a local API with the 17-platform sample.
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
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.20134, longitude: 16.34941))
        app.resetAuthorizationStatus(for: .location)
    }
    override func tearDownWithError() throws {
        app.terminate()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        if maps.state != .notRunning { maps.terminate() }
        server.stop()
        XCUIDevice.shared.location = nil
    }

    func testHomeSampleSquareMapDensityAndOneBatchPerRefresh() {
        launch()
        waitForRows()
        waitUntil { self.server.walkCount == 4 }
        let frame = homeMap.frame
        XCTAssertEqual(frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(frame.height, app.frame.width, accuracy: 1)
        XCTAssertEqual(frame.minY, app.navigationBars.firstMatch.frame.maxY, accuracy: 1)
        let visible = rows.allElementsBoundByIndex.filter { nearbyList.frame.contains($0.frame) }
        print("HOME map=\(frame) list=\(nearbyList.frame) visibleRows=\(visible.count) firstRow=\(rows.firstMatch.frame)")
        XCTAssertGreaterThanOrEqual(visible.count, app.frame.height <= 667 ? 3 : 5)
        XCTAssertEqual(rows.firstMatch.frame.height, 44, accuracy: 0.5)
        visible.forEach { assertTarget($0) }
        XCTAssertEqual(server.radii, [400])
        XCTAssertEqual(server.batchCount, 1)
        XCTAssertEqual(server.individualCount, 0)
        XCTAssertEqual(server.walkCount, 4)
        XCTAssertFalse(app.buttons["refresh-list"].exists)
        XCTAssertFalse(app.staticTexts["board-status"].exists)
        XCTAssertFalse(app.buttons["pin-hint"].exists)
        capture("Home default")
        let before = server.batchCount
        pullToRefresh()
        waitUntil { self.server.batchCount == before + 1 }
        XCTAssertEqual(server.radii, [400])
        XCTAssertEqual(server.walkCount, 4)
    }

    func testFirstLaunchShowsFindingThenRowsWithoutStatus() {
        server.holdBatch()
        launch()
        XCTAssertTrue(app.staticTexts["Finding departures…"].waitForExistence(timeout: 8))
        XCTAssertEqual(rows.count, 0)
        XCTAssertTrue(homeMap.exists)
        server.releaseBatch()
        waitForRows()
        XCTAssertFalse(app.staticTexts["board-status"].exists)
    }

    func testSavedRelaunchShowsClockTimesUntilBatchArrives() {
        launch(); waitForRows()
        let before = Array(rowServices().prefix(2))
        app.terminate()
        server.holdBatch()
        app.launch()
        XCTAssertTrue(app.buttons["refresh-list"].waitForExistence(timeout: 8))
        XCTAssertEqual(Array(rowServices().prefix(2)), before)
        XCTAssertTrue(rows.allElementsBoundByIndex.allSatisfy { !$0.label.contains(". In ") && !$0.label.contains(". Now.") })
        server.releaseBatch()
        XCTAssertTrue(app.buttons["refresh-list"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(rows.firstMatch.label.contains(". In "))
    }

    func testFailedRefreshPreservesRowsAndRecoversInOneBatch() {
        launch(); waitForRows()
        let before = Array(rowServices().prefix(2))
        server.setOffline(true)
        pullToRefresh()
        let refresh = app.buttons["refresh-list"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 8))
        XCTAssertEqual(Array(rowServices().prefix(2)), before)
        XCTAssertEqual(app.buttons.matching(identifier: "refresh-list").count, 1)
        XCTAssertTrue(refresh.label.hasPrefix("Saved times from "))
        XCTAssertTrue(rows.allElementsBoundByIndex.allSatisfy { !$0.label.contains(". In ") && !$0.label.contains(". Now.") })
        assertTarget(refresh)
        capture("Home saved after failure")
        server.setOffline(false)
        let calls = server.batchCount
        refresh.tap()
        XCTAssertTrue(refresh.waitForNonExistence(timeout: 8))
        XCTAssertEqual(server.batchCount, calls + 1)
        XCTAssertEqual(Array(rowServices().prefix(2)), before)
    }

    func testPartialRefreshKeepsSelectionAndOnlyMissingPlatformUsesClock() {
        launch(); waitForRows()
        let before = Array(rowServices().prefix(2))
        server.setMissing(["77704_312"])
        pullToRefresh()
        let banner = app.buttons["refresh-list"]
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        XCTAssertEqual(banner.label, "Some times couldn't update · Retry")
        XCTAssertEqual(Array(rowServices().prefix(2)), before)
        let saved = rows.matching(NSPredicate(format: "label CONTAINS 'Skodagasse'")).firstMatch
        XCTAssertFalse(saved.label.contains(". In "))
        XCTAssertTrue(rows.matching(NSPredicate(format: "label CONTAINS 'Hauptbahnhof'")).firstMatch.label.contains(". In "))
        capture("Home partial refresh")
    }

    func testInitialMissingPlatformsHaveOneRecoveryRowPerStop() {
        server.setMissing(["77704_312", "77704_313", "77704_311", "77704_310"])
        launch()
        XCTAssertTrue(app.buttons["retry-stop"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "retry-stop").count, 1)
        assertTarget(app.buttons["retry-stop"])
        XCTAssertEqual(app.buttons["refresh-list"].label, "Some times couldn't update · Retry")
    }

    func testFirstStopsFailureShowsErrorAndTryAgain() {
        server.setStopsFailed(true)
        launch()
        XCTAssertTrue(app.staticTexts["stops-error"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["empty-stops"].exists)
        XCTAssertFalse(app.staticTexts["Finding departures…"].exists)
        let retry = app.buttons["Try again"]
        assertTarget(retry)
        capture("Home stops failure")
        server.setStopsFailed(false)
        retry.tap()
        waitForRows()
    }

    func testNoStopsOffersWiderSearchAndAreaChoice() {
        server.setEmptyStops(true)
        launch()
        XCTAssertTrue(app.staticTexts["empty-stops"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["empty-stops"].label.hasPrefix("No stops within "))
        let farther = app.buttons["search-farther"]
        assertTarget(farther)
        assertTarget(app.buttons["Choose an area"])
        capture("Home no stops")
        farther.tap()
        waitUntil { self.server.radii.contains(800) }
        XCTAssertEqual(server.radii, [400, 800])
        XCTAssertEqual(server.batchCount, 0)
    }

    func testNoDeparturesHasAnHourMessageAndNoIdleRows() {
        server.setNoDepartures(true)
        launch()
        XCTAssertTrue(app.staticTexts["empty-departures"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["empty-departures"].label, "Nothing leaves here in the next hour")
        XCTAssertEqual(rows.count, 0)
        assertTarget(app.buttons["search-farther"])
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "stop-map-pin").count, 0)
    }

    func testDeniedLocationOffersSettingsAndChosenAreaRemovesNotice() {
        launch(allowLocation: false)
        XCTAssertTrue(app.staticTexts["location-status"].waitForExistence(timeout: 8))
        assertTarget(app.buttons["Open Settings"])
        capture("Home location denied")
        chooseArea()
        waitForRows()
        XCTAssertFalse(app.staticTexts["location-status"].exists)
        XCTAssertTrue(app.buttons["locate"].label.contains("Location is off"))
    }

    func testChoosingAreaResetsListToTopAndSearchTextIsNotTinted() {
        launch(); waitForRows()
        nearbyList.swipeUp()
        nearbyList.swipeUp()
        chooseArea(captureSearch: true)
        waitForRows()
        waitUntil { self.server.centers.last.map { abs($0.0 - 48.204) < 0.00001 } == true }
        XCTAssertTrue(app.navigationBars["New area"].waitForExistence(timeout: 5), app.debugDescription)
        let first = rows.matching(NSPredicate(format: "label CONTAINS 'Skodagasse'")).firstMatch
        XCTAssertTrue(nearbyList.frame.contains(first.frame), "Changing area must reveal the first row again")
        XCTAssertLessThan(first.frame.minY - nearbyList.frame.minY, 65)
        XCTAssertTrue(server.centers.last.map { abs($0.0 - 48.204) < 0.00001 && abs($0.1 - 16.357) < 0.00001 } == true)
        capture("Home changed area at top")
    }

    func testMapOneRowOpensLineAndSeveralRowsScrollAndSelect() {
        launch(); waitForRows()
        let many = app.buttons.matching(NSPredicate(format: "identifier == 'stop-map-pin' AND label CONTAINS 'Subway U3'")).firstMatch
        XCTAssertTrue(many.waitForExistence(timeout: 8), app.debugDescription)
        assertTarget(many)
        many.tap()
        waitUntil { many.isSelected }
        let underground = rows.matching(NSPredicate(format: "label CONTAINS 'Subway U3'")).firstMatch
        XCTAssertTrue(nearbyList.frame.contains(underground.frame))
        capture("Home selected map stop")
        let single = app.buttons.matching(NSPredicate(format: "identifier == 'stop-map-pin' AND label CONTAINS 'Bus 48A'")).firstMatch
        XCTAssertTrue(single.exists)
        single.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS '48A'")).firstMatch.exists)
    }

    func testCountdownLeavesOrderUntouchedAndRowsSpeakNoDecorativeState() {
        launch(); waitForRows()
        let before = Array(rowServices().prefix(2))
        let tick = expectation(description: "countdown tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { tick.fulfill() }
        wait(for: [tick], timeout: 18)
        XCTAssertEqual(Array(rowServices().prefix(2)), before)
        for row in rows.allElementsBoundByIndex {
            XCTAssertFalse(row.isSelected)
            XCTAssertFalse(row.label.contains(". ."))
            XCTAssertFalse(row.label.contains("Scheduled"))
            XCTAssertFalse(row.label.contains("Live"))
            XCTAssertFalse(row.label.contains("Leave"))
            XCTAssertFalse(row.label.contains("Too tight"))
            XCTAssertEqual(row.value as? String ?? "", "")
        }
    }

    func testBoardArrivesDuringScrollAndPublishesAfterRelease() {
        launch(); waitForRows()
        server.setChangedServices()
        server.holdBatch()
        // XCTest waits for a pull-to-refresh control to stop animating before
        // returning from a gesture. Release during that gesture, not after it.
        let fixture = server!
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { fixture.releaseBatch() }
        pullToRefresh(waitForRequest: true)
        nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.8))
            .press(forDuration: 0.2, thenDragTo: nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2)),
                   withVelocity: .slow, thenHoldForDuration: 1)
        nearbyList.swipeDown()
        let gained = rows.matching(NSPredicate(format: "label CONTAINS '99A'")).firstMatch
        XCTAssertTrue(gained.waitForExistence(timeout: 8))
        XCTAssertEqual(server.batchCount, 2)
        // Atomic deferral while the touch is held is asserted in the unit test;
        // this real gesture checks that its deferred update is released.
    }

    func testPinsSurviveRelaunchAndKeepDeepLinks() {
        launch(); waitForRows()
        rows.firstMatch.swipeLeft()
        let pin = app.buttons["pin-route"].firstMatch
        // Swipe actions are system controls; their accessibility frame is not
        // their hit region. The app-drawn row is measured in the density test.
        XCTAssertTrue(pin.exists); pin.tap()
        XCTAssertTrue(app.staticTexts["Pinned"].exists)
        app.terminate(); app.launch(); waitForRows()
        rows.firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["unpin-route"].firstMatch.exists)
        let id = ["77704_312", "bus", "13A", "Wien Skodagasse"].map { "\($0.utf8.count):\($0)" }.joined()
        var link = URLComponents(string: "departs://pin")!
        link.queryItems = [.init(name: "id", value: id)]
        app.open(link.url!)
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["unpin-route"].exists)
    }

    func testAccessibilityMapScrollsAwayAndRowsRemainReadable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(); waitForRows()
        XCTAssertEqual(homeMap.frame.height, app.frame.width, accuracy: 1)
        let initial = homeMap.frame.minY
        capture("Home accessibility map")
        let startY = homeMap.frame.maxY + 60 - nearbyList.frame.minY
        let origin = nearbyList.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: nearbyList.frame.width / 2, dy: startY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: nearbyList.frame.width / 2, dy: 100)),
                   withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(!homeMap.exists || homeMap.frame.minY < initial - 30)
        let first = rows.allElementsBoundByIndex.first { $0.isHittable && nearbyList.frame.contains($0.frame) }
        XCTAssertNotNil(first)
        if let first { assertTarget(first); XCTAssertFalse(first.isSelected) }
        capture("Home accessibility list")
    }

    func testLineSquareMapShowsThreeDeparturesAndTheFourthAfterOneScroll() {
        launch(); waitForRows()
        rows.firstMatch.tap()
        waitUntil { self.server.individualCount == 1 && self.lineRows.count == 4 }
        XCTAssertEqual(lineMap.frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(lineMap.frame.height, app.frame.width, accuracy: 1)
        XCTAssertEqual(lineMap.frame.minY, app.navigationBars.firstMatch.frame.maxY, accuracy: 1)
        XCTAssertTrue(app.descendants(matching: .any)["route-platform"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["route-origin"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "detail-stop-name").count, 1)
        XCTAssertEqual(app.staticTexts["detail-direction"].label, "13A Wien Skodagasse")
        let visible = lineRows.allElementsBoundByIndex.filter { lineList.frame.contains($0.frame) }
        print("LINE map=\(lineMap.frame) list=\(lineList.frame) visibleRows=\(visible.count) firstRow=\(lineRows.firstMatch.frame)")
        XCTAssertGreaterThanOrEqual(visible.count, 3)
        XCTAssertTrue(lineRows.firstMatch.label.contains("Live departure"))
        XCTAssertTrue(lineRows.firstMatch.label.contains("1 min late"))
        XCTAssertFalse(app.staticTexts["Scheduled"].exists)
        XCTAssertFalse(app.staticTexts["departure-advice-title"].exists)
        XCTAssertFalse(app.buttons["show-route-map"].exists)
        capture("Line default")
        if !lineList.frame.contains(lineRows.element(boundBy: 3).frame) { lineList.swipeUp() }
        XCTAssertTrue(lineList.frame.contains(lineRows.element(boundBy: 3).frame))
    }

    func testLineFailedRefreshKeepsClockTimesAndRecoversInOneRequest() {
        launch(); waitForRows(); rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        server.setOffline(true)
        refreshLineByPull()
        let refresh = app.buttons["refresh-line"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(identifier: "refresh-line").count, 1)
        XCTAssertEqual(lineRows.count, 4)
        XCTAssertTrue(lineRows.allElementsBoundByIndex.allSatisfy { !$0.label.contains("In ") && !$0.label.contains("Live departure") })
        assertTarget(refresh)
        capture("Line saved")
        let calls = server.individualCount
        server.setOffline(false)
        refresh.tap()
        XCTAssertTrue(refresh.waitForNonExistence(timeout: 8))
        XCTAssertEqual(server.individualCount, calls + 1)
        XCTAssertTrue(lineRows.firstMatch.label.hasPrefix("In "))
    }

    func testLineEmptyAndBeyondHourUseCalmStateAndClockOnly() {
        launch(); waitForRows()
        server.setLineMinutes([])
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["line-empty"].waitForExistence(timeout: 8))
        XCTAssertEqual(lineRows.count, 0)
        server.setLineMinutes([65, 80, 95, 110])
        refreshLineByPull()
        waitUntil { self.lineRows.count == 4 }
        XCTAssertTrue(app.staticTexts["line-empty"].exists)
        XCTAssertTrue(lineRows.allElementsBoundByIndex.allSatisfy { !$0.label.contains("In ") })
        capture("Line beyond hour")
    }

    func testLineAccessibilityMapScrollsAwayAndFullDestinationRemains() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(); waitForRows()
        let origin = nearbyList.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 180, dy: homeMap.frame.maxY + 60 - nearbyList.frame.minY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 180, dy: 100)), withVelocity: .slow, thenHoldForDuration: 0.2)
        rows.matching(NSPredicate(format: "label CONTAINS 'Skodagasse'")).firstMatch.tap()
        XCTAssertTrue(lineMap.waitForExistence(timeout: 5))
        XCTAssertEqual(lineMap.frame.height, app.frame.width, accuracy: 1)
        let initial = lineMap.frame.minY
        capture("Line accessibility map")
        let listOrigin = lineList.coordinate(withNormalizedOffset: .zero)
        listOrigin.withOffset(CGVector(dx: 180, dy: lineMap.frame.maxY + 50 - lineList.frame.minY))
            .press(forDuration: 0.05, thenDragTo: listOrigin.withOffset(CGVector(dx: 180, dy: 80)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(!lineMap.exists || lineMap.frame.minY < initial - 30)
        XCTAssertEqual(app.staticTexts["detail-direction"].label, "13A Wien Skodagasse")
        XCTAssertTrue(lineRows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(lineRows.firstMatch.isSelected)
        capture("Line accessibility list")
    }

    func testWalkingDirectionsOpensAppleMaps() {
        launch(); waitForRows(); rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        app.buttons["walking-directions"].tap()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 10))
        for title in ["Continue", "Allow Once", "Not Now"] {
            let button = maps.buttons[title].firstMatch
            if button.waitForExistence(timeout: 1) { button.tap() }
        }
        let destination = maps.buttons.matching(NSPredicate(format: "identifier == 'IconImage-WaypointNameText' AND label == 'Siebensterngasse'")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10), maps.debugDescription)
        let walk = maps.buttons["WalkButton"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        waitUntil { walk.frame.width > 0 }
        XCTAssertTrue(walk.isSelected, "Apple Maps must open in walking mode")
        let safety = maps.alerts["Getting There Safely"]
        if safety.waitForExistence(timeout: 2) { safety.buttons["OK"].tap() }
        capture("Apple Maps walking destination")
        print("APPLE_MAPS walkingSelected=\(walk.isSelected) destination=\(destination.label)")
    }

    func testLineWithoutWalkingRouteShowsBothEndpointsAndAreaOrigin() {
        server.setDirectionsFailed(true)
        launch(allowLocation: false)
        chooseArea(); waitForRows(); rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        XCTAssertTrue(app.staticTexts["detail-stop-name"].label.contains("from this area"))
        let origin = app.descendants(matching: .any)["route-origin"]
        XCTAssertTrue(origin.exists)
        XCTAssertEqual(origin.label, "Searched area")
        XCTAssertTrue(app.descendants(matching: .any)["route-platform"].exists)
        XCTAssertTrue(lineMap.exists)
        capture("Line without walking route")
    }

    func testLongLineDestinationWrapsWithoutTruncation() {
        server.useLongDestination()
        launch(); waitForRows(); rows.firstMatch.tap()
        let title = app.staticTexts["detail-direction"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "13A Wien Kaiserebersdorf, Zinnergasse über Hauptbahnhof und Simmering")
        XCTAssertGreaterThan(title.frame.height, 30)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX)
        capture("Line long destination")
    }

    private var lineRows: XCUIElementQuery { app.otherElements.matching(identifier: "line-departure") }
    private var lineList: XCUIElement { app.collectionViews["departure-detail"] }
    private var lineMap: XCUIElement { app.descendants(matching: .any).matching(identifier: "line-map").firstMatch }
    private func refreshLineByPull() {
        let calls = server.individualCount
        lineList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: lineList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        waitUntil { self.server.individualCount > calls }
    }

    private var rows: XCUIElementQuery { app.buttons.matching(identifier: "departure-option") }
    private var nearbyList: XCUIElement { app.collectionViews["nearby-list"] }
    private var homeMap: XCUIElement { app.descendants(matching: .any).matching(identifier: "home-map").firstMatch }
    private func waitForRows() { XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 12), app.debugDescription) }
    private func rowServices() -> [String] {
        rows.allElementsBoundByIndex.map { $0.label.components(separatedBy: ". ").first ?? $0.label }
    }
    private func waitUntil(timeout: TimeInterval = 8, _ predicate: @escaping () -> Bool) {
        let condition = expectation(for: NSPredicate { _, _ in predicate() }, evaluatedWith: nil)
        wait(for: [condition], timeout: timeout)
    }
    private func pullToRefresh(waitForRequest: Bool = true) {
        let count = server.batchCount
        nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        if waitForRequest { waitUntil { self.server.batchCount > count } }
    }
    private func chooseArea(captureSearch: Bool = false) {
        app.buttons["choose-area"].tap()
        let query = app.textFields["area-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap(); query.typeText("New area")
        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
        let result = app.buttons["area-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        assertTarget(result)
        if captureSearch { capture("Search result contrast") }
        result.tap()
    }
    private func launch(allowLocation: Bool = true) {
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            if allowLocation { alert.buttons["Allow While Using App"].tap() }
            else { alert.buttons.matching(NSPredicate(format: "label CONTAINS 'Allow' AND NOT label CONTAINS 'While' AND NOT label CONTAINS 'Once'")).firstMatch.tap() }
        }
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func assertTarget(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.001, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.001, 44, file: file, line: line)
    }
}

private final class TransitFixtureServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "departs.ui-fixtures")
    private var offline = false
    private var stopsFailed = false
    private var directionsFailed = false
    private var emptyStops = false
    private var noDepartures = false
    private var changedServices = false
    private var missing: Set<String> = []
    private var holding = false
    private var heldResponses: [() -> Void] = []
    private var requestedRadii: [Int] = []
    private var requestedCenters: [(Double, Double)] = []
    private var batches = 0
    private var individuals = 0
    private var walks = 0
    private var firstBoardAt: Date?
    private var lineMinutes: [Double]?
    private var longDestination = false

    var baseURL: String { "http://127.0.0.1:\(listener.port!.rawValue)" }
    var batchCount: Int { queue.sync { batches } }
    var individualCount: Int { queue.sync { individuals } }
    var walkCount: Int { queue.sync { walks } }
    var radii: [Int] { queue.sync { requestedRadii } }
    var centers: [(Double, Double)] { queue.sync { requestedCenters } }
    func setOffline(_ value: Bool) { queue.sync { offline = value } }
    func setStopsFailed(_ value: Bool) { queue.sync { stopsFailed = value } }
    func setDirectionsFailed(_ value: Bool) { queue.sync { directionsFailed = value } }
    func setEmptyStops(_ value: Bool) { queue.sync { emptyStops = value } }
    func setNoDepartures(_ value: Bool) { queue.sync { noDepartures = value } }
    func setMissing(_ ids: Set<String>) { queue.sync { missing = ids } }
    func setChangedServices() { queue.sync { changedServices = true } }
    func setLineMinutes(_ values: [Double]) { queue.sync { lineMinutes = values } }
    func useLongDestination() { queue.sync { longDestination = true } }
    func holdBatch() { queue.sync { holding = true } }
    func releaseBatch() { queue.sync {
        holding = false
        let responses = heldResponses; heldResponses = []
        responses.forEach { $0() }
    } }
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
    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var bytes = buffer; bytes.append(data ?? Data())
            guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, buffer: bytes) }
                return
            }
            let path = request.components(separatedBy: " ").dropFirst().first ?? "/"
            let url = URLComponents(string: "http://localhost\(path)")!
            let payload = self.response(to: url)
            let body = try! JSONSerialization.data(withJSONObject: payload)
            let failed = self.offline || self.stopsFailed && url.path == "/api/stops/nearby"
                || self.directionsFailed && url.path == "/api/directions"
            let status = failed ? "503 Service Unavailable" : "200 OK"
            var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            let send = { connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() }) }
            if self.holding, url.queryItems?.contains(where: { $0.name == "stopIds" }) == true { self.heldResponses.append(send) }
            else { send() }
        }
    }
    private func response(to url: URLComponents) -> Any {
        func value(_ name: String) -> String? { url.queryItems?.first { $0.name == name }?.value }
        switch url.path {
        case "/test/places":
            return [["name": "New area", "coordinate": ["lat": 48.204, "lon": 16.357], "source": "chosen"]]
        case "/api/stops/nearby":
            requestedRadii.append(Int(value("radius") ?? "0") ?? 0)
            let lat = Double(value("lat") ?? "0")!, lon = Double(value("lon") ?? "0")!
            requestedCenters.append((lat, lon))
            if emptyStops { return [] as [Any] }
            return TransitSample.stops.map { stop in
                var moved = stop
                let location = stop["location"] as! [String: Double]
                moved["location"] = ["lat": location["lat"]! + lat - 48.20134, "lon": location["lon"]! + lon - 16.34941]
                return moved
            }
        case "/api/departures":
            if firstBoardAt == nil { firstBoardAt = Date() }
            if value("stopIds") != nil {
                batches += 1
                var batch = TransitSample.batch(at: firstBoardAt!, missing: missing, empty: noDepartures, changed: changedServices)
                if longDestination {
                    var boards = batch["boards"] as! [[String: Any]]
                    var groups = boards[0]["groups"] as! [[String: Any]]
                    var line = groups[0]["line"] as! [String: Any]
                    line["direction"] = "Wien Kaiserebersdorf, Zinnergasse über Hauptbahnhof und Simmering"
                    groups[0]["line"] = line
                    boards[0]["groups"] = groups
                    batch["boards"] = boards
                }
                batch["fetchedAt"] = Date().ISO8601Format()
                return batch
            }
            individuals += 1
            let id = value("stopId")?.replacingOccurrences(of: "77704_", with: "") ?? "312"
            var service = TransitSample.services[id]?.first { $0.name == value("lineName") && $0.line["direction"] as? String == value("direction") }
                ?? TransitSample.services["312"]![0]
            if let lineMinutes { service.minutes = lineMinutes }
            return TransitSample.departures(service, at: firstBoardAt!, count: 4)
        case "/api/directions":
            walks += 1
            let from = value("from")!.split(separator: ",").map { Double($0)! }
            let to = value("to")!.split(separator: ",").map { Double($0)! }
            let distance = CLLocation(latitude: from[0], longitude: from[1]).distance(from: CLLocation(latitude: to[0], longitude: to[1]))
            return ["duration": max(45, distance / 1.3), "distance": distance,
                    "geometry": ["type": "LineString", "coordinates": [[from[1], from[0]], [to[1], to[0]]]]]
        default: return ["error": "Unexpected fixture URL"]
        }
    }
}
