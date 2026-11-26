import XCTest
import CoreLocation
import Network
import Vision

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
        app.launchEnvironment["DEPARTS_TEST_WALKING_ROUTES"] = "straight"
        app.launchEnvironment["DEPARTS_DEFAULTS_SUITE"] = "departs-ui-\(UUID().uuidString)"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.20134, longitude: 16.34941))
        app.resetAuthorizationStatus(for: .location)
    }
    override func tearDownWithError() throws {
        app?.terminate()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        if maps.state != .notRunning {
            maps.terminate()
            // A delayed system Contacts alert can outlive Maps, including after
            // a failed assertion. Clear it before the next test launches.
            dismissMapsContactsPrompt(timeout: 2)
        }
        if let server, let testRun, testRun.totalFailureCount > 0 {
            let log = server.eventLog
            print(log)
            let attachment = XCTAttachment(string: log)
            attachment.name = "Fixture server events — \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        server?.stop()
        XCUIDevice.shared.location = nil
    }

    private var padBottomInset: CGFloat {
        let marker = app.descendants(matching: .any)["window-bottom-inset"]
        return CGFloat(Double(marker.value as? String ?? "") ?? .nan)
    }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func testIPadRotationKeepsSelectionAndSplitsBothScreens() throws {
        try XCTSkipUnless(isPad, "Exercises rotatable iPad windows")
        app.launchEnvironment["DEPARTS_TEST_GOOGLE_MAPS"] = "1"
        launch()
        waitForRows()
        assertStacked(homeMap, nearbyList)
        capture("iPad portrait home")
        XCUIDevice.shared.orientation = .landscapeLeft
        assertSplit(homeMap, nearbyList)
        capture("iPad landscape home")
        rows.matching(NSPredicate(format: "label CONTAINS 'Bus 48A'")).firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        assertSplit(lineMap, lineList)
        for control in [app.buttons["line-back"], lineTitle, app.buttons["walking-directions"], app.buttons["pin-route"]] {
            XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.midX)
            XCTAssertLessThanOrEqual(control.frame.maxY, lineList.frame.minY)
        }
        capture("iPad landscape line")
        app.buttons["pin-route"].tap()
        XCTAssertTrue(app.buttons["unpin-route"].exists)
        app.buttons["walking-directions"].tap()
        app.buttons["Apple Maps"].tap()
        waitUntil { self.app.descendants(matching: .any)["opened-map-app"].label == "Apple Maps 1" }
        XCUIDevice.shared.orientation = .portraitUpsideDown
        assertStacked(lineMap, lineList)
        XCTAssertTrue(app.buttons["unpin-route"].exists)
        XCUIDevice.shared.orientation = .portrait
        assertStacked(lineMap, lineList)
        capture("iPad portrait line")
        goBack()
        assertStacked(homeMap, nearbyList)
    }

    func testIPadLandscapeAccessibilityControlsStayInListPane() throws {
        try XCTSkipUnless(isPad, "Exercises accessible iPad panes")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        XCUIDevice.shared.orientation = .landscapeRight
        launch()
        waitForRows()
        assertSplit(homeMap, nearbyList)
        rows.firstMatch.tap()
        waitUntil { self.lineRows.firstMatch.exists }
        assertSplit(lineMap, lineList)
        for id in ["line-back", "walking-directions", "pin-route"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.minX, app.frame.midX)
        }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let split = orientation.isLandscape
            waitUntil { self.app.navigationBars.count == (split ? 0 : 1) }
            for id in ["walking-directions", "pin-route"] {
                XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
            }
            if split { XCTAssertEqual(lineTitle.frame.minX, lineList.frame.minX + 16, accuracy: 1) }
        }
        capture("iPad accessible landscape line")
    }

    func testDirectionChoiceClosesWhenMapResizes() throws {
        try XCTSkipUnless(isPad)
        launch()
        waitForRows()
        let badge = mapLabel("Subway U3")
        badge.tap()
        let choice = app.buttons.matching(identifier: "map-direction").firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        assertSplit(homeMap, nearbyList)
        XCTAssertTrue(choice.waitForNonExistence(timeout: 5))
        capture("Split after dismissing rotated choice")
        badge.tap()
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        capture("Reopened split direction choice")
        choice.tap()
        XCTAssertTrue(lineTitle.waitForExistence(timeout: 5))
    }

    func testShortIPadWindowKeepsTwoDeparturesVisible() throws {
        try XCTSkipUnless(isPad)
        server.useLongDestination()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        launch()
        waitForRows()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let full = app.windows.firstMatch.frame
        func resize(to target: CGPoint) {
            let window = app.windows.firstMatch.frame
            let origin = springboard.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: window.maxX - 5, dy: window.maxY - 5))
                .press(forDuration: 0.6, thenDragTo: origin.withOffset(CGVector(dx: target.x, dy: target.y)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        addTeardownBlock { resize(to: CGPoint(x: full.maxX - 1, y: full.maxY - 1)) }
        resize(to: CGPoint(x: full.minX + 430, y: full.minY + 470))
        waitUntil { self.app.windows.firstMatch.frame.height <= 510 }
        rows.firstMatch.tap()
        waitUntil { self.lineRows.count >= 2 }
        let list = lineList.frame
        XCTAssertTrue(list.contains(lineRows.element(boundBy: 0).frame))
        XCTAssertTrue(list.contains(lineRows.element(boundBy: 1).frame))
        capture("Short window long direction")
    }

    private func assertSplit(_ map: XCUIElement, _ list: XCUIElement) {
        waitUntil { self.app.frame.width > self.app.frame.height && abs(map.frame.maxX - self.app.frame.midX) <= 1 }
        XCTAssertEqual(map.frame.minX, app.frame.minX, accuracy: 1)
        XCTAssertEqual(map.frame.minY, app.frame.minY, accuracy: 1)
        XCTAssertEqual(map.frame.maxY, app.frame.maxY, accuracy: 1)
        XCTAssertEqual(list.frame.minX, map.frame.maxX, accuracy: 1)
        XCTAssertEqual(list.frame.maxX, app.frame.maxX, accuracy: 1)
    }

    private func assertStacked(_ map: XCUIElement, _ list: XCUIElement) {
        waitUntil { self.app.frame.height > self.app.frame.width && abs(map.frame.width - self.app.frame.width) <= 1 }
        XCTAssertGreaterThan(map.frame.minY, app.frame.minY)
        XCTAssertEqual(map.frame.height, (app.frame.maxY - padBottomInset - map.frame.minY) / 2, accuracy: 1)
        XCTAssertEqual(list.frame.width, app.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(list.frame.minY, map.frame.maxY)
    }

    func testHomeSampleSquareMapDensityAndOneBatchPerRefresh() {
        launch()
        waitForRows()
        let frame = homeMap.frame
        XCTAssertEqual(app.navigationBars.count, 0, "Home has no bar: no title and no location button")
        XCTAssertFalse(app.buttons["locate"].exists)
        XCTAssertEqual(frame.width, app.frame.width, accuracy: 1)
        if isPad { assertStacked(homeMap, nearbyList) } else {
            XCTAssertEqual(frame.maxY, topInset + app.frame.width, accuracy: 1, "The square sits under the status bar")
            XCTAssertEqual(frame.minY, reachesTop ? 0 : topInset, accuracy: 1,
                           "On a tall status bar the map continues above the square to the top of the screen")
        }
        XCTAssertEqual(nearbyList.frame.minY, frame.maxY, accuracy: 1)
        // The square shows what it showed before the map reached the top: the
        // rider at its centre and 960 m across, so a stop lands where it did.
        let burggasse = TransitSample.platforms.filter { $0.1 == "Burggasse/Neubaugasse" }
        let expected = squarePoint(latitude: burggasse.map(\.2).reduce(0, +) / Double(burggasse.count),
                                   longitude: burggasse.map(\.3).reduce(0, +) / Double(burggasse.count))
        let label = mapLabel("Bus 48A")
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        print("HOME label=\(label.frame) expected=\(expected)")
        XCTAssertEqual(label.frame.midX, expected.x, accuracy: 3)
        XCTAssertEqual(label.frame.midY, expected.y, accuracy: 3)
        let visible = rows.allElementsBoundByIndex.filter { nearbyList.frame.contains($0.frame) }
        print("HOME map=\(frame) list=\(nearbyList.frame) visibleRows=\(visible.count) firstRow=\(rows.firstMatch.frame)")
        XCTAssertGreaterThanOrEqual(visible.count, app.frame.height <= 667 ? 4 : 6)
        XCTAssertEqual(rows.firstMatch.frame.height, 44, accuracy: 0.5)
        visible.forEach { assertTarget($0) }
        XCTAssertEqual(server.radii, [400])
        XCTAssertEqual(server.batchCount, 1)
        XCTAssertEqual(server.individualCount, 0)
        XCTAssertEqual(server.legacyWalkCount, 0)
        XCTAssertFalse(app.buttons["refresh-list"].exists)
        XCTAssertFalse(app.staticTexts["board-status"].exists)
        XCTAssertFalse(app.buttons["pin-hint"].exists)
        capture("Home default")
        let before = server.batchCount
        pullToRefresh()
        waitUntil { self.server.batchCount == before + 1 }
        XCTAssertEqual(server.radii, [400])
        XCTAssertEqual(server.legacyWalkCount, 0)
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
        XCTAssertFalse(app.buttons["location-retry"].exists, "A saved area with a request running is not a failure")
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

    func testHomeHasNoBarAndOffersNoWiderSearch() {
        launch(); waitForRows()
        XCTAssertEqual(app.navigationBars.count, 0, "No title, no location button, no search")
        XCTAssertFalse(app.buttons["locate"].exists)
        XCTAssertFalse(app.buttons["location-retry"].exists)
        for _ in 0..<3 { nearbyList.swipeUp() }
        XCTAssertFalse(app.buttons["search-farther"].exists)
        XCTAssertFalse(app.buttons["Choose an area"].exists)
        XCTAssertEqual(server.radii, [400])
        capture("Home end of list")
    }

    func testNoStopsSaysSoAndOffersNoOtherSearch() {
        server.setEmptyStops(true)
        launch()
        XCTAssertTrue(app.staticTexts["empty-stops"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["empty-stops"].label.hasPrefix("No stops within "))
        XCTAssertFalse(app.buttons["search-farther"].exists)
        XCTAssertFalse(app.buttons["Choose an area"].exists)
        capture("Home no stops")
        pullToRefresh(waitForRequest: false)
        XCTAssertEqual(Set(server.radii), [400])
        XCTAssertEqual(server.batchCount, 0)
    }

    func testNoDeparturesHasAnHourMessageAndNoIdleRows() {
        server.setNoDepartures(true)
        launch()
        XCTAssertTrue(app.staticTexts["empty-departures"].waitForExistence(timeout: 10),
                      "stops=\(server.radii) batches=\(server.batchCount) \(app.debugDescription)")
        XCTAssertEqual(app.staticTexts["empty-departures"].label, "Nothing leaves here in the next hour")
        XCTAssertEqual(rows.count, 0)
        XCTAssertFalse(app.buttons["search-farther"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "stop-map-pin").count, 0)
    }

    func testLocationOffShowsSettingsAndPinnedRoutesOnly() {
        launch(); waitForRows()
        rows.firstMatch.swipeLeft()
        app.buttons["pin-route"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pinned"].waitForExistence(timeout: 5))
        app.terminate()
        app.resetAuthorizationStatus(for: .location)
        launch(allowLocation: false)
        XCTAssertTrue(app.staticTexts["location-status"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["location-status"].label.hasPrefix("Location is off"))
        assertTarget(app.buttons["Open Settings"])
        XCTAssertEqual(rows.count, 0, "No departures for a place the rider may have left")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "stop-map-pin").count, 0)
        XCTAssertEqual(app.navigationBars.count, 0)
        XCTAssertFalse(app.buttons["location-retry"].exists, "Location off has its own notice")
        XCTAssertFalse(app.buttons["Choose an area"].exists)
        capture("Home location off")
        let batches = server.batchCount
        let elsewhere = app.buttons["Pinned elsewhere (1)"]
        assertTarget(elsewhere)
        elsewhere.tap()
        let pinned = app.buttons.matching(NSPredicate(format: "label CONTAINS '13A toward Wien Skodagasse'")).firstMatch
        XCTAssertTrue(pinned.waitForExistence(timeout: 5))
        pinned.tap()
        waitUntil { self.lineRows.count == 4 }
        XCTAssertEqual(app.staticTexts["detail-stop-name"].label, "Siebensterngasse")
        XCTAssertTrue(app.descendants(matching: .any)["route-platform"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["route-origin"].exists, "No walk can start from an unknown place")
        XCTAssertEqual(server.batchCount, batches)
        capture("Line pinned with location off")
    }

    func testMovingToAnotherPlaceResetsTheListToTheTopAndLooksThere() {
        launch(); waitForRows()
        nearbyList.swipeUp()
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.204, longitude: 16.357))
        // Pull to refresh asks for a new fix, as the location button used to.
        // The drag first brings the list back, so pull until the fix is asked for.
        for _ in 0..<3 where server.centers.count < 2 { pullToRefresh(waitForRequest: false) }
        waitUntil(timeout: 20) { self.server.centers.last.map { abs($0.0 - 48.204) < 0.0002 && abs($0.1 - 16.357) < 0.0002 } == true }
        let first = rows.matching(NSPredicate(format: "label CONTAINS 'Skodagasse'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(nearbyList.frame.contains(first.frame), "A new area must reveal the first row again")
        XCTAssertLessThan(first.frame.minY - nearbyList.frame.minY, 65)
        XCTAssertEqual(Set(server.radii), [400])
        XCTAssertEqual(app.navigationBars.count, 0)
        capture("Home after moving")
    }

    func testCoarseFixExplainsItselfAndAPreciseOneRecovers() {
        // What Precise Location off produces: a fix arrives, too coarse to use.
        app.launchEnvironment["DEPARTS_TEST_LOCATION_ACCURACY"] = "800"
        launch()
        let status = app.staticTexts["location-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(status.label.hasPrefix("Couldn't find your location"))
        XCTAssertFalse(app.staticTexts["Finding departures…"].exists)
        assertTarget(app.buttons["Try again"])
        assertTarget(app.buttons["Open Settings"])
        XCTAssertFalse(app.buttons["location-retry"].exists, "Without a saved area the full explanation stands alone")
        XCTAssertEqual(rows.count, 0)
        XCTAssertEqual(server.radii, [], "Nothing is searched from a place this uncertain")
        capture("Home location not found")
        app.buttons["Try again"].tap()
        XCTAssertTrue(status.waitForExistence(timeout: 12), "Still coarse: the explanation returns")
        XCTAssertEqual(server.radii, [])
        app.terminate()
        app.launchEnvironment["DEPARTS_TEST_LOCATION_ACCURACY"] = nil
        app.launch()
        waitForRows()
        XCTAssertFalse(status.exists)
        XCTAssertFalse(app.buttons["location-retry"].exists)
        XCTAssertEqual(app.navigationBars.count, 0)
    }

    func testCoarseFixKeepsTheLastAreaAndNamesWhereTheWalkStarts() {
        launch(); waitForRows()
        let label = mapLabel("Subway U3")
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        let saved = label.frame
        app.terminate()
        app.launchEnvironment["DEPARTS_TEST_LOCATION_ACCURACY"] = "800"
        app.launch()
        let retry = app.buttons["location-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertEqual(retry.label, "Couldn't find your location · Try again")
        assertTarget(retry)
        XCTAssertEqual(app.buttons.matching(identifier: "location-retry").count, 1)
        XCTAssertEqual(app.navigationBars.count, 0)
        waitForRows()
        XCTAssertLessThan(retry.frame.minY, rows.firstMatch.frame.minY, "The row comes first in the list")
        waitUntil(timeout: 15) { self.rows.firstMatch.label.contains(". In ") || self.rows.firstMatch.label.contains(". Now.") }
        XCTAssertFalse(app.staticTexts["location-status"].exists, "A saved area is more use than an apology")
        // The map stands on the saved area, ring included, as it did before.
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(label.frame.midX, saved.midX, accuracy: 3)
        XCTAssertEqual(label.frame.midY, saved.midY, accuracy: 3)
        capture("Home last area without a usable fix")
        let stops = server.radii.count
        retry.tap()
        // Still coarse: the row returns and nothing new is searched.
        XCTAssertTrue(retry.waitForExistence(timeout: 12))
        XCTAssertEqual(server.radii.count, stops)
        rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        let origin = app.descendants(matching: .any)["route-origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 5))
        XCTAssertEqual(origin.label, "Last location")
        XCTAssertTrue(app.staticTexts["detail-stop-name"].label.contains("from this area"))
        capture("Line from the last area")
    }

    func testMapBadgeOpensItsLineOrOffersItsDirections() {
        launch(); waitForRows()
        let directions = app.buttons.matching(identifier: "map-direction")
        // U3 runs both ways from its stop: its badge offers the two directions.
        let both = mapLabel("Subway U3")
        XCTAssertTrue(both.waitForExistence(timeout: 8), app.debugDescription)
        assertTarget(both)
        both.tap()
        XCTAssertTrue(directions.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(directions.allElementsBoundByIndex.map(\.label), ["Subway U3 toward Wien Simmering", "Subway U3 toward Wien Ottakring"])
        directions.allElementsBoundByIndex.forEach { assertTarget($0) }
        XCTAssertTrue(both.isSelected)
        XCTAssertFalse(lineMap.exists, "Nothing opens before a direction is chosen")
        // The choice carries no times: the list below has them.
        let frames = directions.allElementsBoundByIndex.map(\.frame)
        let shown = recognizedText(in: frames.dropFirst().reduce(frames[0]) { $0.union($1) })
        print("CHOICE text=\(shown) frames=\(frames)")
        XCTAssertTrue(shown.contains { $0.contains("Simmering") }, "\(shown)")
        XCTAssertFalse(shown.contains { $0.range(of: #"\d\s*min|Now|\d{1,2}:\d{2}"#, options: .regularExpression) != nil }, "\(shown)")
        capture("Home map direction choice")
        // Closed without a direction: nothing is selected, and nothing opened.
        dismissChoice()
        waitUntil { !both.isSelected }
        XCTAssertFalse(lineMap.exists)
        // A direction opens that line.
        both.tap()
        XCTAssertTrue(directions.firstMatch.waitForExistence(timeout: 5))
        directions.matching(NSPredicate(format: "label CONTAINS 'Ottakring'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(lineTitle.label.contains("Ottakring"), lineTitle.label)
        goBack()
        // 48A runs one way from its stop: its badge opens the line, and a
        // label that is still selected answers the next tap too.
        let single = mapLabel("Bus 48A")
        for attempt in 1...2 {
            XCTAssertTrue(single.waitForExistence(timeout: 5))
            single.tap()
            XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5), "Tap \(attempt) on the label opens its line")
            XCTAssertTrue(lineTitle.label.contains("48A"), lineTitle.label)
            XCTAssertFalse(directions.firstMatch.exists)
            goBack()
        }
        XCTAssertTrue(single.waitForExistence(timeout: 5))
        XCTAssertTrue(single.isSelected, "The stop keeps its ring after its line was opened")
    }

    func testEachBadgeOfALabelIsItsOwnLine() {
        launch(); waitForRows()
        let directions = app.buttons.matching(identifier: "map-direction")
        // Siebensterngasse: 13A and 49, each in two directions.
        let label = mapLabel("Tram 49")
        XCTAssertTrue(label.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(label.label.contains("Bus 13A"))
        label.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        XCTAssertTrue(directions.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(directions.allElementsBoundByIndex.map(\.label), ["Bus 13A toward Wien Skodagasse", "Bus 13A toward Wien Hauptbahnhof"])
        dismissChoice()
        label.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        XCTAssertTrue(directions.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(directions.allElementsBoundByIndex.map(\.label),
                       ["Tram 49 toward Wien Parlament/Volkstheater", "Tram 49 toward Wien Hütteldorf, Bujattigasse"])
        directions.matching(NSPredicate(format: "label CONTAINS 'Hütteldorf'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(lineTitle.label.contains("Hütteldorf"), lineTitle.label)
    }

    func testHomeMapIgnoresDragAndPinchAndLabelsStillWork() {
        launch(); waitForRows()
        let label = mapLabel("Subway U3")
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        let home = label.frame
        homeMap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: homeMap.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        homeMap.swipeLeft()
        homeMap.pinch(withScale: 2.5, velocity: 1)
        homeMap.pinch(withScale: 0.4, velocity: -1)
        // Beside every label: a double tap must not zoom, and it is no tap on a badge.
        homeMap.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.25)).doubleTap()
        // Give any animation time to finish before measuring.
        let settle = expectation(description: "settle"); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertTrue(label.exists)
        XCTAssertEqual(label.frame.midX, home.midX, accuracy: 1, "A drag must not pan the home map")
        XCTAssertEqual(label.frame.midY, home.midY, accuracy: 1)
        XCTAssertEqual(label.frame.width, home.width, accuracy: 1, "A pinch must not zoom it")
        XCTAssertEqual(server.radii, [400])
        XCTAssertFalse(app.buttons["map-direction"].exists, "None of those gestures is a tap on a badge")
        label.tap()
        waitUntil { label.isSelected }
        XCTAssertTrue(app.buttons["map-direction"].waitForExistence(timeout: 5))
        dismissChoice()
        let single = mapLabel("Bus 48A")
        XCTAssertTrue(single.exists)
        single.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
    }

    func testHomeMapFollowsASmallMoveWithoutLoadingStops() {
        launch(); waitForRows()
        let label = mapLabel("Bus 48A")
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        let before = label.frame, services = rowServices(), stops = server.radii.count
        // About 100 m north of the test coordinate.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.20134 + 100 / 111_200, longitude: 16.34941))
        let expected = 100 * (isPad ? homeMap.frame.height : app.frame.width) / 960
        let started = Date()
        waitUntil(timeout: 5) { abs(label.frame.midY - before.midY - expected) < 4 }
        print("FOLLOW shift=\(label.frame.midY - before.midY) expected=\(expected) after=\(Date().timeIntervalSince(started))s")
        XCTAssertEqual(label.frame.midX, before.midX, accuracy: 2)
        XCTAssertEqual(server.radii.count, stops, "A move shorter than 150 m loads no stops")
        XCTAssertEqual(rowServices(), services, "The list stays put")
        capture("Home after a 100 m move")
    }

    private func launchOverflowingList() {
        let extraStops = isPad ? 10 : 0
        server.useExtraStops(extraStops)
        launch()
        waitForRows()
    }

    func testStopNameLeavesWithItsLastLine() {
        launchOverflowingList()
        checkStopNameLeavesWithItsLastLine()
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            // A fresh list starts at the top in the new orientation.
            app.terminate()
            app.launch()
            waitForRows()
            assertSplit(homeMap, nearbyList)
            checkStopNameLeavesWithItsLastLine()
        }
    }

    private func checkStopNameLeavesWithItsLastLine() {
        let list = nearbyList.frame
        // Two stops are both called Neubaugasse, so lines are matched by place:
        // a stop's lines are the rows between its name and the next name.
        let headers = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Siebensterngasse", "Burggasse/Neubaugasse", "Neubaugasse"]))
        var checkedAtTop = 0, pinnedWhilePassing = 0, pinnedY: CGFloat?, previous: CGFloat?
        // The header's area reaches below its text: measure the gap to the first line.
        let firstName = headers.matching(NSPredicate(format: "label == 'Siebensterngasse'")).firstMatch.frame
        let gap = rows.firstMatch.frame.minY - firstName.maxY
        XCTAssertGreaterThanOrEqual(gap, 0)
        var capturedLeavingHeader = false
        for step in 0..<45 {
            let names = headers.allElementsBoundByIndex.filter { $0.exists }.map(\.frame)
                .filter { $0.maxY > list.minY + 0.5 && $0.minY < list.maxY }.sorted { $0.minY < $1.minY }
            let lines = rows.allElementsBoundByIndex.map(\.frame)
            for (index, name) in names.enumerated() {
                // A name entering at the bottom comes before its first line, as in
                // any list. The rule is about the top: a name there, pinned or
                // leaving, never covers its last line. One of its lines must show
                // whole below the name's area. A sliver under the name is not a line.
                guard name.minY <= list.minY + 20 else { continue }
                if isPad {
                    // Countdowns pass behind this otherwise blank part of the name.
                    let trailing = CGRect(x: list.maxX - 72, y: name.minY + 2, width: 54,
                                          height: max(0, name.height - 4)).intersection(list)
                    if trailing.height >= 3 {
                        let ink = darkestPixel(in: trailing)
                        if !capturedLeavingHeader, list.minX > 0, name.minY < list.minY + 9 {
                            capture("Split header leaving")
                            capturedLeavingHeader = true
                        }
                        if ink <= 245 {
                            print("HEADER step=\(step) frame=\(name) sample=\(trailing) list=\(list) grey=\(ink)")
                            capture("Rows behind header")
                        }
                        XCTAssertGreaterThan(ink, 245,
                                             "A departing row must be completely hidden behind its pinned name")
                    }
                }
                let next = index + 1 < names.count ? names[index + 1].minY : list.maxY
                let shown = lines.contains {
                    $0.minY >= name.maxY + gap - 1 && $0.minY >= list.minY - 0.5 && $0.maxY <= list.maxY + 0.5 && $0.minY < next
                }
                XCTAssertTrue(shown, "Step \(step): a stop name at \(name) with none of its lines clear of it")
                if !shown { capture("Stop name without lines") }
                checkedAtTop += 1
            }
            let stopLines = rows.matching(NSPredicate(format: "label ENDSWITH 'From Siebensterngasse.'")).allElementsBoundByIndex.map(\.frame)
            let first = headers.matching(NSPredicate(format: "label == 'Siebensterngasse'")).firstMatch
            if stopLines.count == 4, first.exists {
                let name = first.frame
                // While the first three lines pass under the name and the fourth
                // has not reached it, the name holds one position at the top.
                if stopLines[0].minY < name.maxY - 1, stopLines[3].minY > name.maxY + 1 {
                    if pinnedY == nil { pinnedY = name.minY }
                    XCTAssertEqual(name.minY, pinnedY!, accuracy: 1, "Step \(step): the name must stay at the top")
                    XCTAssertLessThan(name.minY - list.minY, 20)
                    pinnedWhilePassing += 1
                }
            }
            if isPad && pinnedWhilePassing > 1 && checkedAtTop > 3 && !first.isHittable { break }
            let marker = rows.allElementsBoundByIndex.last?.frame.minY
            if let marker, let previous, abs(marker - previous) < 0.5, step > 2 { break }
            previous = marker
            let start = nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -30)),
                        withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        print("STICKY checkedAtTop=\(checkedAtTop) pinnedWhilePassing=\(pinnedWhilePassing) pinnedY=\(pinnedY ?? -1) gap=\(gap) list=\(list)")
        XCTAssertGreaterThan(pinnedWhilePassing, 1, "The scroll never passed the first stop's lines under its name")
        XCTAssertGreaterThan(checkedAtTop, 3)
    }

    func testPinnedStopNameKeepsItsColour() {
        launchOverflowingList()
        checkPinnedStopNameKeepsItsColour()
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            // A fresh list starts at the top in the new orientation.
            app.terminate()
            app.launch()
            waitForRows()
            assertSplit(homeMap, nearbyList)
            checkPinnedStopNameKeepsItsColour()
        }
    }

    private func checkPinnedStopNameKeepsItsColour() {
        let name = app.staticTexts.matching(NSPredicate(format: "label == 'Siebensterngasse'")).firstMatch
        let unpinned = darkestPixel(in: name.frame)
        // Scroll until the first line has passed under the name.
        for _ in 0..<6 where rows.firstMatch.frame.minY >= name.frame.maxY {
            let start = nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -30)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertLessThan(rows.firstMatch.frame.minY, name.frame.maxY, "The name must be pinned for this check")
        let pinned = darkestPixel(in: name.frame)
        print("NAME colour unpinned=\(unpinned) pinned=\(pinned)")
        XCTAssertEqual(pinned, unpinned, "A pinned stop name must keep the colour of an unpinned one")
        if isPad && app.frame.width > app.frame.height {
            XCTAssertGreaterThan(nearbyList.frame.minY, 0, "Scrolled rows must stay below the status region")
            let clearBand = CGRect(x: nearbyList.frame.midX - 40, y: 4, width: 80, height: nearbyList.frame.minY - 6)
            XCTAssertGreaterThan(darkestPixel(in: clearBand), 245)
            capture("Split scrolled home")
        } else {
            capture("Pinned stop name")
        }
    }

    func testCountdownsShowNoInButStillSpeakIt() {
        launch(); waitForRows()
        let home = recognizedText()
        print("OCR home: \(home)")
        XCTAssertTrue(home.contains { $0.range(of: #"^\d+ min$"#, options: .regularExpression) != nil }, "\(home)")
        XCTAssertFalse(home.contains { $0.range(of: #"\bIn \d"#, options: .regularExpression) != nil }, "\(home)")
        XCTAssertTrue(rows.firstMatch.label.contains(". In "), "VoiceOver keeps the full phrase")
        capture("Home countdowns")
        rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        let line = recognizedText()
        print("OCR line: \(line)")
        XCTAssertTrue(line.contains { $0.range(of: #"^\d+ min$"#, options: .regularExpression) != nil }, "\(line)")
        XCTAssertFalse(line.contains { $0.range(of: #"\bIn \d"#, options: .regularExpression) != nil }, "\(line)")
        XCTAssertTrue(lineRows.firstMatch.label.hasPrefix("In "), "VoiceOver keeps the full phrase")
        capture("Line countdowns")
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
        let gained = rows.matching(NSPredicate(format: "label CONTAINS '99A'")).firstMatch
        // A second downward gesture on an iPad with all rows in view can request another refresh.
        if !isPad { nearbyList.swipeDown() }
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

    func testPinnedElsewhereFollowsTheAreaAndKeepsThePinReachableByLink() {
        launch(); waitForRows()
        rows.firstMatch.swipeLeft()
        app.buttons["pin-route"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pinned"].waitForExistence(timeout: 5))
        let elsewhere = app.buttons["Pinned elsewhere (1)"]
        XCTAssertFalse(elsewhere.exists, "The nearby pin has its own row")

        // Leave the fixture's stops behind, first within Vienna, then in New York.
        server.setEmptyStops(true)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.22, longitude: 16.34941))
        pullToRefresh(waitForRequest: false)
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 12))
        XCTAssertEqual(rows.count, 0)
        elsewhere.tap()
        let pinned = app.buttons.matching(NSPredicate(format: "label CONTAINS '13A toward Wien Skodagasse'")).firstMatch
        XCTAssertTrue(pinned.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.7128, longitude: -74.0060))
        pullToRefresh(waitForRequest: false)
        waitUntil(timeout: 12) { self.server.centers.last.map { abs($0.0 - 40.7128) < 0.0002 } == true }
        XCTAssertTrue(elsewhere.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Pinned"].exists)

        let id = ["77704_312", "bus", "13A", "Wien Skodagasse"].map { "\($0.utf8.count):\($0)" }.joined()
        var link = URLComponents(string: "departs://pin")!
        link.queryItems = [.init(name: "id", value: id)]
        app.open(link.url!)
        XCTAssertTrue(app.buttons["unpin-route"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail-stop-name"].label, "Siebensterngasse")
    }

    func testAccessibilityMapScrollsAwayAndRowsRemainReadable() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(); waitForRows()
        if isPad {
            XCTAssertEqual(homeMap.frame.height, (app.frame.maxY - padBottomInset - homeMap.frame.minY) / 2, accuracy: 1)
            XCTAssertGreaterThan(homeMap.frame.minY, 0)
        } else {
            XCTAssertEqual(homeMap.frame.height, app.frame.width, accuracy: 1)
            XCTAssertEqual(homeMap.frame.minY, topInset, accuracy: 1)
        }
        XCTAssertEqual(app.navigationBars.count, 0)
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
        // The map has home's frame: the square under the status bar, and the
        // strip above it on a tall status bar. No bar is drawn (O22).
        XCTAssertEqual(app.navigationBars.count, 0, "At standard sizes the line screen has no bar")
        XCTAssertEqual(lineMap.frame.width, app.frame.width, accuracy: 1)
        if isPad { assertStacked(lineMap, lineList) } else {
            XCTAssertEqual(lineMap.frame.maxY, topInset + app.frame.width, accuracy: 1, "The square sits under the status bar, as on home")
            XCTAssertEqual(lineMap.frame.minY, reachesTop ? 0 : topInset, accuracy: 1)
        }
        // Under the map: back, the line and its direction, walk, pin.
        let back = app.buttons["line-back"], walk = app.buttons["walking-directions"], pin = app.buttons["pin-route"]
        let summary = app.staticTexts["detail-stop-name"]
        for control in [back, walk, pin] {
            assertTarget(control)
            XCTAssertGreaterThanOrEqual(control.frame.minY, lineMap.frame.maxY - 0.5, "\(control)")
        }
        XCTAssertEqual(back.label, "Back")
        XCTAssertLessThanOrEqual(back.frame.maxX, lineTitle.frame.minX + 0.5)
        XCTAssertLessThanOrEqual(lineTitle.frame.maxX, walk.frame.minX + 0.5)
        XCTAssertLessThanOrEqual(walk.frame.maxX, pin.frame.minX + 0.5)
        XCTAssertEqual(back.frame.midY, lineTitle.frame.midY, accuracy: 3, "The buttons align with the title's line")
        XCTAssertEqual(pin.frame.midY, back.frame.midY, accuracy: 0.5)
        XCTAssertEqual(summary.frame.minX, lineTitle.frame.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(summary.frame.minY, lineTitle.frame.maxY - 0.5, "The stop sits under the line and direction")
        XCTAssertGreaterThanOrEqual(lineList.frame.minY, summary.frame.maxY - 0.5, "The list starts below the controls")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == '13A Wien Skodagasse'")).count, 1, "The line is named once")
        XCTAssertEqual(app.staticTexts.matching(identifier: "detail-stop-name").count, 1)
        XCTAssertEqual(lineTitle.label, "13A Wien Skodagasse")
        // MapKit keeps the route inside the square, clear of the status bar.
        let square = isPad ? lineMap.frame : CGRect(x: 0, y: topInset, width: app.frame.width, height: app.frame.width)
        let platform = app.descendants(matching: .any)["route-platform"], start = app.descendants(matching: .any)["route-origin"]
        XCTAssertTrue(platform.exists)
        XCTAssertTrue(start.exists)
        print("LINE square=\(square) platform=\(platform.frame) origin=\(start.frame) controls=\(back.frame) \(lineTitle.frame) \(walk.frame) \(pin.frame)")
        XCTAssertTrue(square.contains(CGPoint(x: platform.frame.midX, y: platform.frame.midY)), "\(platform.frame)")
        XCTAssertTrue(square.contains(CGPoint(x: start.frame.midX, y: start.frame.midY)), "\(start.frame)")
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

    func testLineCountdownsShareOneRightAlignedColumn() {
        launch(); waitForRows(); rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        // The countdowns are drawn inside each row's single accessibility
        // element, so they are found on screen: "2 min", "6 min", "10 min", "14 min".
        let countdowns = recognizedCountdownBoxes().filter {
            $0.text.range(of: #"^\d+ min$"#, options: .regularExpression) != nil && $0.frame.minX < app.frame.width / 2
        }
        print("COUNTDOWNS \(countdowns.map { "\($0.text) \($0.frame)" })")
        XCTAssertEqual(countdowns.count, 4, "\(countdowns)")
        XCTAssertTrue(countdowns.contains { $0.text.count == 5 } && countdowns.contains { $0.text.count == 6 })
        let rights = countdowns.map(\.frame.maxX), lefts = countdowns.map(\.frame.minX)
        XCTAssertLessThan(rights.max()! - rights.min()!, 2, "Right-aligned: every countdown ends at one x")
        XCTAssertGreaterThan(lefts.max()! - lefts.min()!, 5, "A two-digit countdown starts further left")
        capture("Line countdown column")
    }

    func testLineScreenGoesBackWithItsButtonAndTheEdgeSwipe() {
        launch(); waitForRows()
        func open() {
            rows.firstMatch.tap()
            XCTAssertTrue(lineMap.waitForExistence(timeout: 5))
            waitUntil { self.lineRows.count == 4 }
        }
        /// A drag across most of the width completes a pop on its progress; a
        /// short fast one can be cancelled by UIKit, as with a finger.
        func drag(fromX x0: CGFloat, to x1: CGFloat, y: CGFloat, velocity: XCUIGestureVelocity) {
            let size = app.frame.size
            app.coordinate(withNormalizedOffset: CGVector(dx: x0 / size.width, dy: y / size.height))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: x1 / size.width, dy: y / size.height)),
                       withVelocity: velocity, thenHoldForDuration: 0)
        }
        let width = app.frame.width
        open()
        let back = app.buttons["line-back"]
        back.tap()
        XCTAssertTrue(lineMap.waitForNonExistence(timeout: 5), "The back button goes back")
        // With the bar hidden, the swipe from the left edge goes back from
        // every height: over the map, the controls and the list.
        var heights: [String] = []
        for place in ["map middle", "map bottom", "controls", "list"] {
            open()
            let y: CGFloat
            switch place {
            case "map middle": y = lineMap.frame.midY
            case "map bottom": y = lineMap.frame.maxY - 60
            case "controls": y = app.staticTexts["detail-stop-name"].frame.midY
            default: y = lineList.frame.midY
            }
            drag(fromX: 0, to: width * 0.95, y: y, velocity: 600)
            heights.append("\(place) y=\(Int(y))")
            XCTAssertTrue(lineMap.waitForNonExistence(timeout: 5), "The edge swipe goes back from the \(place), y = \(Int(y))")
            if lineMap.exists { back.tap(); XCTAssertTrue(lineMap.waitForNonExistence(timeout: 5)) }
        }
        print("SWIPES \(heights)")
        // A pan on the map still pans and stays, also one that starts 30 pt
        // from the left edge.
        open()
        let platform = app.descendants(matching: .any)["route-platform"]
        for startX in [width * 0.4, 30] {
            let before = platform.frame
            drag(fromX: startX, to: startX + width * 0.4, y: lineMap.frame.midY, velocity: 300)
            let moved = expectation(for: NSPredicate { _, _ in platform.exists && platform.frame.midX > before.midX + 60 }, evaluatedWith: nil)
            wait(for: [moved], timeout: 5)
            print("PAN from x=\(Int(startX)): \(before.midX) -> \(platform.frame.midX)")
            XCTAssertTrue(lineMap.exists, "A pan from x = \(Int(startX)) stays on the line screen")
        }
        back.tap()
        XCTAssertTrue(lineMap.waitForNonExistence(timeout: 5))
        // On home there is nothing to go back to: the swipe changes nothing,
        // and home still answers a tap. It crosses the map, which takes no
        // drag; a fast drag that starts on a row can open that row's line.
        drag(fromX: 0, to: width * 0.95, y: homeMap.frame.maxY - 30, velocity: 600)
        XCTAssertTrue(homeMap.waitForExistence(timeout: 3))
        XCTAssertFalse(lineMap.exists)
        rows.firstMatch.tap()
        XCTAssertTrue(lineMap.waitForExistence(timeout: 5), "Home still opens a line after a swipe at its edge")
    }

    /// While the line screen is shown, every other gesture waits for the swipe
    /// from the left edge to fail. Touches that start at the edge but do not
    /// swipe right still do what they did.
    func testEdgeSwipeLeavesTapsLongPressesAndScrollsAlone() {
        app.launchEnvironment["DEPARTS_TEST_GOOGLE_MAPS"] = "1"
        launch(); waitForRows()
        func open(atX x: CGFloat) {
            rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: x, dy: 0)).tap()
            XCTAssertTrue(lineMap.waitForExistence(timeout: 5), "A tap \(Int(x)) pt into a home row opens its line")
            waitUntil { self.lineRows.count == 4 }
        }
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        }
        let back = app.buttons["line-back"], walk = app.buttons["walking-directions"]
        let opened = app.descendants(matching: .any)["opened-map-app"]
        func choice(_ name: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch }
        // The back button starts 4 pt from the edge: a tap on its outer part
        // still goes back, as one on its centre does.
        var timings: [String] = []
        for dx in [0.5, 0.1] as [CGFloat] {
            open(atX: dx == 0.5 ? rows.firstMatch.frame.width / 2 : 4)
            let x = Int(back.frame.minX + back.frame.width * dx), start = Date()
            back.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            XCTAssertTrue(lineMap.waitForNonExistence(timeout: 3), "A tap at x = \(x) goes back")
            timings.append("back x=\(x) \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        }
        // After a swipe back too, home's rows answer a tap at their left end.
        open(atX: 4)
        point(0, lineList.frame.midY).press(forDuration: 0.05, thenDragTo: point(app.frame.width * 0.95, lineList.frame.midY),
                                            withVelocity: 600, thenHoldForDuration: 0)
        XCTAssertTrue(lineMap.waitForNonExistence(timeout: 5))
        open(atX: 4)
        // A long press on walk opens the choice while the finger is still down:
        // sliding to Apple Maps and lifting picks it.
        walk.tap()
        XCTAssertTrue(choice("Google Maps").waitForExistence(timeout: 3))
        let apple = choice("Apple Maps").frame
        choice("Google Maps").tap()
        waitUntil { opened.label == "Google Maps 1" }
        walk.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2, thenDragTo: point(apple.midX, apple.midY), withVelocity: .slow, thenHoldForDuration: 0.3)
        waitUntil { opened.label == "Apple Maps 2" }
        XCTAssertFalse(choice("Google Maps").exists)
        // A pull to refresh that starts at the edge still refreshes.
        let calls = server.individualCount
        point(2, lineList.frame.minY + lineList.frame.height * 0.2)
            .press(forDuration: 0.1, thenDragTo: point(2, lineList.frame.minY + lineList.frame.height * 0.95),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        waitUntil { self.server.individualCount > calls }
        XCTAssertTrue(lineMap.exists, "A pull from the edge stays on the line screen")
        // At accessibility sizes the list scrolls: a vertical scroll that
        // starts at the edge moves it as far as one that starts in the middle.
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch(); waitForRows()
        rows.matching(NSPredicate(format: "label CONTAINS 'Skodagasse'")).firstMatch.tap()
        XCTAssertTrue(lineMap.waitForExistence(timeout: 5))
        var scrolled: [CGFloat] = []
        for x in [app.frame.width / 2, 2] {
            let before = lineMap.frame.minY, y = lineMap.frame.maxY + 40
            point(x, y + 150).press(forDuration: 0.05, thenDragTo: point(x, y), withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertTrue(lineMap.exists, "A scroll from x = \(Int(x)) stays on the line screen")
            scrolled.append(before - lineMap.frame.minY)
            point(app.frame.width / 2, y).press(forDuration: 0.05, thenDragTo: point(app.frame.width / 2, y + 150),
                                                 withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        print("EDGE_OTHERS \(timings) scrolled=\(scrolled)")
        XCTAssertGreaterThan(scrolled[1], 60, "A scroll from the edge moves the list")
        XCTAssertEqual(scrolled[1], scrolled[0], accuracy: 30, "and about as far as one from the middle")
    }

    func testStopLineRunsUnderTheButtonsOnOneLine() {
        launch(); waitForRows()
        rows.matching(NSPredicate(format: "label CONTAINS 'Bus 48A'")).firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        let summary = app.staticTexts["detail-stop-name"], walk = app.buttons["walking-directions"], pin = app.buttons["pin-route"]
        waitUntil { summary.label.contains("walk") && summary.label.contains("m") }
        print("STOPLINE \(summary.label) \(summary.frame) title=\(lineTitle.frame) walk=\(walk.frame)")
        // "Burggasse/Neubaugasse · 4 min walk · 310 m" needs more room than
        // the title has beside the buttons; it runs on under them.
        XCTAssertEqual(summary.frame.minX, lineTitle.frame.minX, accuracy: 0.5)
        if !isPad { XCTAssertGreaterThan(summary.frame.maxX, walk.frame.minX, "The stop line passes under walk and pin") }
        if app.frame.width >= 402 {
            XCTAssertLessThan(summary.frame.height, 26, "One line on a 402 pt phone: \(summary.frame)")
        } else {
            // Narrower, it may wrap, but no line starts with the dot.
            let lines = recognizedText(in: summary.frame.insetBy(dx: -2, dy: -2))
            print("STOPLINE lines=\(lines)")
            XCTAssertFalse(lines.contains { $0.hasPrefix("·") || $0.hasPrefix("•") }, "\(lines)")
        }
        XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.width - 16 + 0.5, "It stops at the list's margin")
        XCTAssertGreaterThanOrEqual(summary.frame.minY, lineTitle.frame.maxY - 0.5)
        // The title wraps here; the buttons stay on its first line.
        if !isPad { XCTAssertGreaterThan(lineTitle.frame.height, 30, "This title wraps beside the buttons") }
        XCTAssertEqual(walk.frame.midY, lineTitle.frame.minY + 10.2, accuracy: 3, "The buttons stay on the title's first line")
        XCTAssertEqual(pin.frame.midY, walk.frame.midY, accuracy: 0.5)
        capture("Line stop line under the buttons")
    }

    func testLineDividersStartWhereTheRowStarts() {
        launch(); waitForRows(); rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        func starts(_ situation: String) {
            // Rows whose bottom edge, where the divider is, lies on screen.
            let frames = lineRows.allElementsBoundByIndex.map(\.frame).filter { $0.maxY + 1 < lineList.frame.maxY }
            let found = frames.compactMap { separatorStart(below: $0) }
            print("DIVIDERS \(situation): \(found) rows=\(frames.count)")
            XCTAssertGreaterThanOrEqual(frames.count, 2, "\(situation)")
            XCTAssertEqual(found.count, frames.count, "\(situation): a divider under every row shown")
            for x in found {
                XCTAssertEqual(x, lineList.frame.minX + 16, accuracy: 1, "\(situation): every divider starts at the row's leading edge")
            }
            capture("Line dividers, \(situation)")
        }
        starts("2, 6, 10 and 14 min")
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            assertSplit(lineMap, lineList)
            starts("split")
        }
        server.setLineMinutes([0.5, 4, 10, 16])
        refreshLineByPull()
        waitUntil { self.lineRows.firstMatch.label.hasPrefix("Now") }
        starts("Now, 4, 10 and 16 min")
        server.setOffline(true)
        refreshLineByPull()
        XCTAssertTrue(app.buttons["refresh-line"].waitForExistence(timeout: 8))
        waitUntil { !self.lineRows.firstMatch.label.contains("min") }
        starts("saved clock times")
    }

    func testLineFailedRefreshKeepsClockTimesAndRecoversInOneRequest() {
        launch(); waitForRows(); rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        server.setOffline(true)
        refreshLineByPull()
        let refresh = app.buttons["refresh-line"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons.matching(identifier: "refresh-line").count, 1)
        // The banner pushes rows outside the SE's lazy list viewport. Cache
        // retention is covered by the store test; inspect the rendered rows.
        XCTAssertGreaterThan(lineRows.count, 0)
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
        XCTAssertTrue(lineRows.firstMatch.waitForExistence(timeout: 8))
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
        XCTAssertEqual(lineMap.frame.height, isPad ? (app.frame.maxY - padBottomInset - lineMap.frame.minY) / 2 : app.frame.width, accuracy: 1)
        // At accessibility sizes the bar stays, with back, walk and pin (A39).
        XCTAssertEqual(app.navigationBars.count, 1)
        XCTAssertFalse(app.buttons["line-back"].exists)
        XCTAssertTrue(app.buttons["walking-directions"].exists)
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
        // Maps plans a walk only with its own location permission. On a new
        // simulator run xcrun simctl bootstatus <id> -b, then grant it:
        // xcrun simctl privacy <id> grant location com.apple.Maps.
        // Granting it through the prompt makes iOS ask about Maps widgets later,
        // on top of whichever test is running.
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        app.buttons["walking-directions"].tap()
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 10))

        // Observed layouts: Maps 26 uses waypoint cells on both phones; Maps 27
        // uses waypoint buttons on the larger phone. Rows are origin, destination.
        // Maps 27 reuses the button identifier for its separate Add Stop action.
        // On the small phone, Maps 27 uses a compact "To <stop>" title inside
        // IOSRoutePlanningOverview; its narrower header is absent on Maps 27.2.
        let route = maps.otherElements["IOSRoutePlanningOverview"].firstMatch
        let waypointCells = route.cells.matching(identifier: "RoutePlanningWaypointCell")
        let waypointButtons = route.buttons.matching(NSPredicate(format:
            "identifier == 'IconImage-WaypointNameText' AND label != 'Add Stop'"))
        let overviewDestination = route.staticTexts.matching(NSPredicate(format:
            "identifier == 'TitleLabel' AND label == 'To Siebensterngasse'")).firstMatch
        func matchedDestination() -> (label: String, layout: String)? {
            if waypointCells.count == 2 {
                let destination = waypointCells.element(boundBy: 1)
                let label = destination.label
                if label == "Siebensterngasse" { return (label, "waypoint-cell") }
            }
            if waypointButtons.count == 2 {
                let destination = waypointButtons.element(boundBy: 1)
                let label = destination.label
                if label == "Siebensterngasse" { return (label, "waypoint-button") }
            }
            if overviewDestination.exists { return (overviewDestination.label, "compact-overview") }
            return nil
        }
        let walk = maps.buttons.matching(NSPredicate(format: "identifier == 'WalkButton' OR label == 'Walk'")).firstMatch

        // First-run sheets can arrive after Maps reaches the foreground. Keep
        // handling them while waiting for the route instead of giving up after
        // a one-second gap. Each dismissed sheet starts the next transition's
        // ten-second wait without shortening the existing deadline. A fresh
        // iOS 27.2 simulator took 89 seconds to show its first sheet, so allow
        // 120 seconds for that initial transition.
        // Never reopen Maps or tap Departs' walk button again.
        var transitionDeadline = Date().addingTimeInterval(120)
        var dismissed = 0
        while Date() < transitionDeadline {
            if dismissMapsContactsPrompt() {
                dismissed += 1
                transitionDeadline = max(transitionDeadline, Date().addingTimeInterval(10))
            } else if let prompt = ["Continue", "Not Now"].map({ maps.buttons[$0].firstMatch })
                .first(where: { $0.exists && $0.isHittable }) {
                prompt.tap()
                dismissed += 1
                transitionDeadline = max(transitionDeadline, Date().addingTimeInterval(10))
            } else if matchedDestination() != nil {
                break
            } else {
                Thread.sleep(forTimeInterval: 0.2)
            }
            if dismissed >= 6 { break }
        }
        // Check again after route readiness: a system prompt may arrive after
        // the loop exits. tearDown also clears it if an assertion fails.
        dismissMapsContactsPrompt(timeout: 2)
        capture("Apple Maps walking destination")
        let hierarchy = XCTAttachment(string: maps.debugDescription)
        hierarchy.name = "Apple Maps route hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let destination = matchedDestination()
        XCTAssertNotNil(destination, "Apple Maps must show Siebensterngasse as the route destination\n\(maps.debugDescription)")
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        waitUntil { walk.frame.width > 0 }
        XCTAssertTrue(walk.isSelected, "Apple Maps must open in walking mode")
        let safety = maps.alerts["Getting There Safely"]
        if safety.waitForExistence(timeout: 2) { safety.buttons["OK"].tap() }
        dismissMapsContactsPrompt(timeout: 2)
        capture("Apple Maps walking route after prompts")
        if let destination {
            print("APPLE_MAPS walkingSelected=\(walk.isSelected) destination=\(destination.label) layout=\(destination.layout)")
        }
    }

    func testWalkButtonOffersMapAppsThenRemembersAndALongPressAsksAgain() {
        // The simulator has no Google Maps: this Debug hook stands one in, and
        // records which app would open instead of leaving the app.
        app.launchEnvironment["DEPARTS_TEST_GOOGLE_MAPS"] = "1"
        launch(); waitForRows(); rows.firstMatch.tap()
        let walk = app.buttons["walking-directions"]
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        XCTAssertEqual(walk.label, "Walking directions")
        let opened = app.descendants(matching: .any)["opened-map-app"]
        XCTAssertTrue(opened.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(opened.label, "none")
        func choice(_ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        }
        walk.tap()
        XCTAssertTrue(choice("Google Maps").waitForExistence(timeout: 3), "The first tap offers the choice: \(app.debugDescription)")
        XCTAssertTrue(choice("Apple Maps").exists)
        XCTAssertEqual(opened.label, "none", "Nothing opens before a choice")
        capture("Map apps choice")
        choice("Google Maps").tap()
        waitUntil { opened.label == "Google Maps 1" }
        walk.tap()
        waitUntil { opened.label == "Google Maps 2" }
        XCTAssertFalse(choice("Apple Maps").exists, "A remembered app opens without asking")
        walk.press(forDuration: 1.2)
        XCTAssertTrue(choice("Apple Maps").waitForExistence(timeout: 3), "A long press shows the choice again")
        capture("Map apps choice after a long press")
        choice("Apple Maps").tap()
        waitUntil { opened.label == "Apple Maps 3" }
        walk.tap()
        waitUntil { opened.label == "Apple Maps 4" }
        app.terminate(); app.launch(); waitForRows(); rows.firstMatch.tap()
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        walk.tap()
        waitUntil { opened.label == "Apple Maps 1" }
        XCTAssertFalse(choice("Google Maps").exists, "The choice is remembered across launches")
    }

    func testLineWithoutWalkingRouteStillShowsBothEndpoints() {
        app.launchEnvironment["DEPARTS_TEST_WALKING_ROUTES"] = "unavailable"
        launch(); waitForRows(); rows.firstMatch.tap()
        waitUntil { self.lineRows.count == 4 }
        XCTAssertEqual(app.staticTexts["detail-stop-name"].label, "Siebensterngasse")
        let origin = app.descendants(matching: .any)["route-origin"]
        XCTAssertTrue(origin.exists)
        XCTAssertEqual(origin.label, "Walking start")
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
        if !isPad { XCTAssertGreaterThan(title.frame.height, 30) }
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX)
        capture("Line long destination")
    }

    func testLineWithAPlusInItsDestinationShowsDepartures() {
        server.usePlusDestination()
        launch(); waitForRows(); rows.firstMatch.tap()
        let title = app.staticTexts["detail-direction"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.hasSuffix(" S+U Pankow"), title.label)
        waitUntil { self.server.individualCount == 1 && self.lineRows.count == 4 }
        XCTAssertFalse(app.staticTexts["line-empty"].exists)
    }

    func testUSMeasurementPreferenceUsesFeetInWalkingSummary() {
        app.launchArguments += ["-AppleMeasurementUnits", "Inches", "-AppleMetricUnits", "NO"]
        launch(); waitForRows(); rows.firstMatch.tap()
        let summary = app.staticTexts["detail-stop-name"]
        waitUntil { summary.label.contains("ft") }
        XCTAssertFalse(summary.label.hasSuffix(" m"))
        capture("Line US units")
    }

    #if PSEUDO_LOCALIZATION
    func testGermanRegionWithExpandedPseudoLocalization() {
        for accessibility in [false, true] {
            app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
            if accessibility {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            launch()
            XCTAssertTrue(homeMap.waitForExistence(timeout: 8))
            if accessibility {
                // Expanded headers can fill the entire space below the map.
                // Scroll before asking the lazy list for its first row.
                let origin = nearbyList.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: 180, dy: homeMap.frame.maxY + 60 - nearbyList.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 180, dy: 100)),
                           withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            waitForRows()
            let first = rows.firstMatch
            XCTAssertTrue(first.label.contains("［"), "The disposable German catalog must actually be loaded")
            XCTAssertFalse(first.label.contains(". ."))
            assertTarget(first)
            capture(accessibility ? "Pseudo home accessibility" : "Pseudo home default")
            first.tap()
            XCTAssertTrue(lineMap.waitForExistence(timeout: 5))
            if accessibility {
                let initial = lineMap.frame.minY
                let origin = lineList.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: 180, dy: lineMap.frame.maxY + 50 - lineList.frame.minY))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 180, dy: 80)),
                           withVelocity: .slow, thenHoldForDuration: 0.2)
                XCTAssertTrue(!lineMap.exists || lineMap.frame.minY < initial - 30)
            }
            let summary = app.staticTexts["detail-stop-name"]
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            XCTAssertTrue(summary.label.contains("Fußweg"))
            XCTAssertLessThanOrEqual(summary.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(summary.frame.height, accessibility ? 40 : 17)
            if accessibility {
                for _ in 0..<3 where !lineRows.firstMatch.exists { lineList.swipeUp() }
            }
            XCTAssertTrue(lineRows.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(lineRows.firstMatch.label.contains("［In "))
            capture(accessibility ? "Pseudo line accessibility" : "Pseudo line default")
            app.terminate()
        }
    }
    #endif

    private var lineRows: XCUIElementQuery { app.otherElements.matching(identifier: "line-departure") }
    private var lineList: XCUIElement { app.collectionViews["departure-detail"] }
    private var lineMap: XCUIElement { app.descendants(matching: .any).matching(identifier: "line-map").firstMatch }
    /// The line and its direction, under the line map at standard sizes.
    private var lineTitle: XCUIElement { app.staticTexts["detail-direction"] }
    /// The line screen's back button sits under the map at standard sizes,
    /// and in the bar at accessibility sizes.
    private func goBack() {
        let back = app.buttons["line-back"]
        if back.exists { back.tap() } else { app.navigationBars.buttons.firstMatch.tap() }
        XCTAssertTrue(lineMap.waitForNonExistence(timeout: 5))
    }
    private func refreshLineByPull() {
        let calls = server.individualCount
        lineList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: lineList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        waitUntil { self.server.individualCount > calls }
    }

    private var rows: XCUIElementQuery { app.buttons.matching(identifier: "departure-option") }
    private func mapLabel(_ service: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'stop-map-pin' AND label CONTAINS %@", service)).firstMatch
    }
    /// The status bar's height: home has no bar, so its square starts there.
    /// iPhone 17 Pro and the 667-point display measured 62 and 20 points.
    private var topInset: CGFloat { app.frame.height <= 667 ? 20 : 62 }
    /// A tall status bar lets the map continue above the square to the top of
    /// the screen. The 20-point bar of the 667-point display does not.
    private var reachesTop: Bool { topInset >= 44 }
    /// Where home draws a coordinate: the test location is the centre of the
    /// square under the status bar, and the square spans 960 m.
    private func squarePoint(latitude: Double, longitude: Double) -> CGPoint {
        let rider = CLLocation(latitude: 48.20134, longitude: 16.34941)
        let north = CLLocation(latitude: latitude, longitude: rider.coordinate.longitude).distance(from: rider)
            * (latitude < rider.coordinate.latitude ? -1 : 1)
        let east = CLLocation(latitude: rider.coordinate.latitude, longitude: longitude).distance(from: rider)
            * (longitude < rider.coordinate.longitude ? -1 : 1)
        let scale = (isPad ? homeMap.frame.height : app.frame.width) / 960
        return CGPoint(x: app.frame.width / 2 + east * scale, y: (isPad ? homeMap.frame.midY : topInset + app.frame.width / 2) - north * scale)
    }
    private func uprightScreenshot() -> CGImage? {
        let image = XCUIScreen.main.screenshot().image
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }.cgImage
    }

    /// The darkest grey level drawn inside a frame: a name's ink in light mode.
    private func darkestPixel(in frame: CGRect) -> Int {
        guard let image = uprightScreenshot() else { return -1 }
        let scale = CGFloat(image.width) / app.frame.width
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return -1 }
        let box = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale).integral
        var darkest = 255
        for y in max(0, Int(box.minY))..<min(height, Int(box.maxY)) {
            for x in max(0, Int(box.minX))..<min(width, Int(box.maxX)) { darkest = min(darkest, Int(pixels[y * width + x])) }
        }
        return darkest
    }
    /// Closes a choice of directions by touching the list beside it.
    private func dismissChoice() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertTrue(app.buttons["map-direction"].waitForNonExistence(timeout: 5))
    }
    /// Where a list divider drawn along a row's bottom edge starts, in points:
    /// the leftmost pixel of the longest run that differs from the background.
    private func separatorStart(below frame: CGRect) -> CGFloat? {
        guard let image = uprightScreenshot() else { return nil }
        let pane = lineList.frame
        let scale = CGFloat(image.width) / app.frame.width
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let x0 = max(0, Int(pane.minX * scale) + 1), x1 = min(width, Int(pane.maxX * scale) - 1)
        var best: (start: Int, length: Int)?
        for y in Int((frame.maxY - 1.5) * scale)...Int((frame.maxY + 1.5) * scale) where y >= 0 && y < height {
            let background = Int(pixels[y * width + x0])
            var start: Int?, length = 0
            for x in x0..<x1 {
                if abs(Int(pixels[y * width + x]) - background) >= 6 {
                    if start == nil { start = x }
                    length += 1
                } else if let first = start {
                    if length > (best?.length ?? 0) { best = (first, length) }
                    start = nil; length = 0
                }
            }
            if let first = start, length > (best?.length ?? 0) { best = (first, length) }
        }
        guard let best, CGFloat(best.length) > pane.width * scale / 2 else { return nil }
        return CGFloat(best.start) / scale
    }

    /// Countdown frames in screen points. On iPad, measure glyph ink in the leading 150 pt of the line list.
    private func recognizedCountdownBoxes() -> [(text: String, frame: CGRect)] {
        guard var image = uprightScreenshot() else { return [] }
        var region = app.frame
        if isPad {
            // Vision downscales large screenshots. Read the countdown column at native resolution.
            region = CGRect(x: lineList.frame.minX, y: lineList.frame.minY,
                            width: 150, height: lineList.frame.height)
            let scale = CGFloat(image.width) / app.frame.width
            guard let crop = image.cropping(to: region.applying(CGAffineTransform(scaleX: scale, y: scale))) else { return [] }
            image = crop
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let size = region.size
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            var frame = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                               width: box.width * size.width, height: box.height * size.height)
            if isPad {
                // Vision's word boxes can end several points past the final glyph.
                // Measure the actual ink on each recognized line at the original pixel scale.
                let scale = CGFloat(image.width) / size.width
                let line = CGRect(x: 0, y: frame.minY - 2, width: size.width, height: frame.height + 4)
                guard let band = image.cropping(to: line.applying(CGAffineTransform(scaleX: scale, y: scale))),
                      let edges = inkColumns(in: band) else { return nil }
                frame.origin.x = CGFloat(edges.lowerBound) / scale
                frame.size.width = CGFloat(edges.count) / scale
            }
            return (text, frame.offsetBy(dx: region.minX, dy: region.minY))
        }
    }
    /// Horizontal extent of dark text in a light-mode screenshot of one line.
    private func inkColumns(in image: CGImage) -> ClosedRange<Int>? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let columns = (0..<width).filter { x in
                (0..<height).contains { y in buffer[y * width + x] < 128 }
            }
            guard let first = columns.first, let last = columns.last else { return nil }
            return first...last
        }
    }

    /// Text as drawn on screen, or in one part of it. A row's spoken label
    /// differs from what it shows.
    private func recognizedText(in frame: CGRect? = nil) -> [String] {
        guard var image = uprightScreenshot() else { return [] }
        if let frame {
            let scale = CGFloat(image.width) / app.frame.width
            let box = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            guard let part = image.cropping(to: box.integral) else { return [] }
            image = part
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
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
    @discardableResult
    private func dismissMapsContactsPrompt(timeout: TimeInterval = 0) -> Bool {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts
            .matching(NSPredicate(format: "label CONTAINS 'Maps'")).firstMatch
        // iOS 27.2 exposes two nested denial buttons with this identifier.
        let deny = alert.buttons.matching(identifier: "kTCCServiceAddressBook-deny-button").firstMatch
        guard timeout > 0 ? deny.waitForExistence(timeout: timeout) : deny.exists else { return false }
        deny.tap()
        return true
    }
    private func launch(allowLocation: Bool = true) {
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        // A new simulator can also ask about Maps widgets, even with Maps'
        // location granted through simctl. Answer it and keep looking.
        for _ in 0..<2 where alert.waitForExistence(timeout: 5) {
            if alert.label.contains("widgets") || !alert.buttons["Allow While Using App"].exists {
                alert.buttons["Don’t Allow"].firstMatch.tap()
                continue
            }
            if allowLocation { alert.buttons["Allow While Using App"].tap() }
            else { alert.buttons.matching(NSPredicate(format: "label CONTAINS 'Allow' AND NOT label CONTAINS 'While' AND NOT label CONTAINS 'Once'")).firstMatch.tap() }
            break
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
    private var legacyWalks = 0
    private var firstBoardAt: Date?
    private var lineMinutes: [Double]?
    private var longDestination = false
    private var plusDestination = false
    private var events: [String] = []
    private var nextConnectionID = 0

    // All event bookkeeping runs on the same queue as the listener and connections.
    var eventLog: String { queue.sync { events.joined(separator: "\n") } }
    private func record(_ event: String) {
        let timestamp = Date().ISO8601Format(.init(includingFractionalSeconds: true))
        events.append("FIXTURE_SERVER_LOG \(timestamp) \(event.replacingOccurrences(of: "\n", with: "\\n"))")
        if events.count > 200 { events.removeFirst(events.count - 200) }
    }
    private func cancel(_ connection: NWConnection, id: Int, reason: String) {
        record("connection=\(id) cancel reason=\(reason)")
        connection.cancel()
    }

    var baseURL: String { "http://127.0.0.1:\(listener.port!.rawValue)" }
    var batchCount: Int { queue.sync { batches } }
    var individualCount: Int { queue.sync { individuals } }
    var legacyWalkCount: Int { queue.sync { legacyWalks } }
    var radii: [Int] { queue.sync { requestedRadii } }
    var centers: [(Double, Double)] { queue.sync { requestedCenters } }
    func setOffline(_ value: Bool) { queue.sync { offline = value } }
    func setStopsFailed(_ value: Bool) { queue.sync { stopsFailed = value } }
    func setEmptyStops(_ value: Bool) { queue.sync { emptyStops = value } }
    func setNoDepartures(_ value: Bool) { queue.sync { noDepartures = value } }
    func setMissing(_ ids: Set<String>) { queue.sync { missing = ids } }
    func setChangedServices() { queue.sync { changedServices = true } }
    func setLineMinutes(_ values: [Double]) { queue.sync { lineMinutes = values } }
    func useLongDestination() { queue.sync { longDestination = true } }
    func usePlusDestination() { queue.sync { plusDestination = true } }
    private var extraStops = 0
    func useExtraStops(_ count: Int) { queue.sync { extraStops = count } }
    private var extraPlatforms: [(String, String, Double, Double)] {
        (0..<extraStops).map { i in
            ("9\(100 + i)", "Fixture stop \(i + 1)", 48.20134 + Double(i % 5 - 2) * 0.0006,
             16.34941 + (i < 5 ? -0.0016 : 0.0016) + Double(i % 2) * 0.0003)
        }
    }
    private func extraServices(_ i: Int) -> [TransitSample.Service] {
        [.init(name: "E\(i + 1)", direction: "Fixture east \(i + 1)", mode: "bus", minutes: [4, 12, 20, 28]),
         .init(name: "F\(i + 1)", direction: "Fixture west \(i + 1)", mode: "tram", minutes: [7, 17, 27, 37])]
    }

    func holdBatch() { queue.sync { holding = true } }
    func releaseBatch() { queue.sync {
        holding = false
        let responses = heldResponses; heldResponses = []
        responses.forEach { $0() }
    } }
    init() throws { listener = try NWListener(using: .tcp, on: .any) }
    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            self?.record("listener \(state)")
            if case .ready = state { ready() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.nextConnectionID += 1
            let id = self.nextConnectionID
            self.record("connection=\(id) accepted")
            connection.start(queue: self.queue)
            self.receive(connection, id: id, buffer: Data())
        }
        listener.start(queue: queue)
    }
    func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, id: Int, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            if let error {
                self.record("connection=\(id) ended before complete request bytes=\(buffer.count + (data?.count ?? 0)) error=\(error)")
                self.cancel(connection, id: id, reason: "receive error")
                return
            }
            var bytes = buffer; bytes.append(data ?? Data())
            guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete {
                    self.record("connection=\(id) ended before complete request bytes=\(bytes.count) error=none (EOF)")
                    self.cancel(connection, id: id, reason: "incomplete request")
                } else { self.receive(connection, id: id, buffer: bytes) }
                return
            }
            let path = request.components(separatedBy: " ").dropFirst().first ?? "/"
            let url = URLComponents(string: "http://localhost\(path)")!
            let method = request.components(separatedBy: " ").first ?? "?"
            self.record("connection=\(id) request method=\(method) path=\(url.percentEncodedPath) query=\(url.percentEncodedQuery ?? "")")
            let payload = self.response(to: url)
            let body = try! JSONSerialization.data(withJSONObject: payload)
            let failed = self.offline || self.stopsFailed && url.path == "/api/stops/nearby"
            let status = failed ? "503 Service Unavailable" : "200 OK"
            var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            let send = { [weak self] in
                self?.record("connection=\(id) response status=\(status) bytes=\(response.count) bodyBytes=\(body.count)")
                connection.send(content: response, completion: .contentProcessed { [weak self] error in
                    guard let self else { connection.cancel(); return }
                    self.record("connection=\(id) send completed error=\(error.map { String(describing: $0) } ?? "none")")
                    self.cancel(connection, id: id, reason: "send completed")
                })
            }
            if self.holding, url.queryItems?.contains(where: { $0.name == "stopIds" }) == true { self.heldResponses.append(send) }
            else { send() }
        }
    }
    private func response(to url: URLComponents) -> Any {
        func value(_ name: String) -> String? { url.queryItems?.first { $0.name == name }?.value }
        switch url.path {
        case "/api/stops/nearby":
            requestedRadii.append(Int(value("radius") ?? "0") ?? 0)
            let lat = Double(value("lat") ?? "0")!, lon = Double(value("lon") ?? "0")!
            requestedCenters.append((lat, lon))
            if emptyStops { return [] as [Any] }
            let extras: [[String: Any]] = extraPlatforms.enumerated().map { i, platform in
                ["id": "77704_\(platform.0)", "name": platform.1, "type": "bus",
                 "location": ["lat": platform.2 + lat - 48.20134, "lon": platform.3 + lon - 16.34941],
                 "lines": extraServices(i).map(\.line)]
            }
            return TransitSample.stops.map { stop in
                var moved = stop
                let location = stop["location"] as! [String: Double]
                moved["location"] = ["lat": location["lat"]! + lat - 48.20134, "lon": location["lon"]! + lon - 16.34941]
                return moved
            } + extras
        case "/api/departures":
            if firstBoardAt == nil { firstBoardAt = Date() }
            if value("stopIds") != nil {
                batches += 1
                var batch = TransitSample.batch(at: firstBoardAt!, missing: missing, empty: noDepartures, changed: changedServices)
                if longDestination || plusDestination {
                    var boards = batch["boards"] as! [[String: Any]]
                    var groups = boards[0]["groups"] as! [[String: Any]]
                    var line = groups[0]["line"] as! [String: Any]
                    line["direction"] = plusDestination ? "S+U Pankow"
                        : "Wien Kaiserebersdorf, Zinnergasse über Hauptbahnhof und Simmering"
                    groups[0]["line"] = line
                    boards[0]["groups"] = groups
                    batch["boards"] = boards
                }
                if extraStops > 0 {
                    var boards = batch["boards"] as! [[String: Any]]
                    for (i, platform) in extraPlatforms.enumerated() {
                        let groups: [[String: Any]] = extraServices(i).map {
                            ["line": $0.line, "departures": TransitSample.departures($0, at: firstBoardAt!)]
                        }
                        boards.append(["stopId": "77704_\(platform.0)", "groups": groups])
                    }
                    batch["boards"] = boards
                }
                batch["fetchedAt"] = Date().ISO8601Format()
                return batch
            }
            individuals += 1
            if plusDestination {
                // Read the query as a server does, where a raw "+" is a space, and
                // match exactly: a plus the app leaves raw selects nothing.
                let direction = url.percentEncodedQueryItems?.first { $0.name == "direction" }?.value?
                    .replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                if direction != "S+U Pankow" { return [] as [Any] }
            }
            let id = value("stopId")?.replacingOccurrences(of: "77704_", with: "") ?? "312"
            var service = TransitSample.services[id]?.first { $0.name == value("lineName") && $0.line["direction"] as? String == value("direction") }
                ?? TransitSample.services["312"]![0]
            if let lineMinutes { service.minutes = lineMinutes }
            return TransitSample.departures(service, at: firstBoardAt!, count: 4)
        case "/api/directions":
            legacyWalks += 1
            fallthrough
        default: return ["error": "Unexpected fixture URL"]
        }
    }
}
