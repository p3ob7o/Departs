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
        XCUIDevice.shared.orientation = .portrait
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
        for _ in 0..<3 where !disclosure.isHittable { nearbyList.swipeUp() }
        assertTarget(disclosure)
        disclosure.tap()
        let future = app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Tram 55 toward'")).firstMatch
        XCTAssertTrue(future.waitForExistence(timeout: 4))
        XCTAssertFalse(future.label.contains("Leave"))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label BEGINSWITH 'Nothing soon. Tram 56'")).firstMatch.exists)
        capture("Expanded future and idle lines")
        // The expanded group's button frame includes its children. Its label
        // has the header's own frame, so it remains an unambiguous tap target.
        let disclosureLabel = nearbyList.staticTexts["2 lines with nothing soon"]
        XCTAssertTrue(disclosureLabel.exists)
        disclosureLabel.tap()
        XCTAssertFalse(future.isHittable, "The idle group must be closed before refreshing")
        for _ in 0..<5 where rows.firstMatch.frame.minY < 120 { nearbyList.swipeDown() }
        server.setChangedServices()
        let beforeRefresh = server.radii.count
        nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
            .press(forDuration: 0.1, thenDragTo: nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 0.5)
        let refreshed = expectation(for: NSPredicate { _, _ in self.server.radii.count > beforeRefresh }, evaluatedWith: nil)
        wait(for: [refreshed], timeout: 5)
        let gained = app.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Tram 56 toward'")).firstMatch
        let repartitioned = expectation(for: NSPredicate(format: "label CONTAINS 'Tram 50 toward'"), evaluatedWith: rows.firstMatch)
        wait(for: [repartitioned], timeout: 8)
        for _ in 0..<4 where !gained.exists { nearbyList.swipeUp() }
        XCTAssertTrue(gained.waitForExistence(timeout: 4))
        let lost = nearbyList.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'Tram 49 toward'")).firstMatch
        capture("Changed boards after refresh")
        XCTAssertFalse(lost.isHittable, "The line that lost departures belongs in the collapsed group")
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
        nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            .press(forDuration: 0.2, thenDragTo: nearbyList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)), withVelocity: .slow, thenHoldForDuration: 2)
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
            nearbyList.swipeUp()
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
            nearbyList.swipeUp()
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
        XCTAssertEqual(departureScroll.staticTexts.matching(NSPredicate(format: "label == 'Volkstheater'")).count, 1)
        app.buttons["show-route-map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.maps.firstMatch.isHittable)
        capture("Route map sheet")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["departure-too-tight"].exists)
        let other = app.buttons["other-line"].firstMatch
        for _ in 0..<6 {
            if other.isHittable && other.frame.maxY < app.buttons["walking-directions"].frame.minY { break }
            departureScroll.swipeUp()
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
        bringIntoView(app.buttons["show-route-map"], in: departureScroll)
        assertTarget(app.buttons["show-route-map"])
        print("ADVICE accessibility height=\(app.staticTexts["departure-advice-detail"].frame.height)")
        capture("Advice at accessibility text size")
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

    func testWindowResizePreservesSelectedBoardAndOpenSheet() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        server.setExtendedStops()
        launchAndAllowLocation()
        guard UIDevice.current.userInterfaceIdiom == .pad,
              XCUIScreen.main.screenshot().image.size.width >= 1300 else {
            throw XCTSkip("The full window range uses the 13-inch iPad destination")
        }
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 12))
        resizeWindow(width: 1200, height: 650)
        app.buttons["departure-option"].firstMatch.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        let chosen = nearbyList.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'from Extra stop 4'")).firstMatch
        for _ in 0..<12 where !chosen.isHittable { nearbyList.swipeUp() }
        XCTAssertTrue(chosen.isHittable)
        let listAnchor = visibleListOrder().first!
        let detailTitle = app.navigationBars["49 Hütteldorf"]
        XCTAssertTrue(detailTitle.exists)
        for _ in 0..<6 where app.staticTexts["detail-direction"].isHittable {
            departureScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05,
                       thenDragTo: departureScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let scrolledHeading = departureScroll.staticTexts["Next departures"]
        XCTAssertTrue(scrolledHeading.isHittable)
        XCTAssertFalse(app.staticTexts["detail-direction"].isHittable)
        capture("Window split before resizing")
        for width in [375.0, 669.0, 1200.0] {
            resizeWindow(width: width, height: 650)
            XCTAssertTrue(detailTitle.exists, "The selected board survives every column transition")
            XCTAssertTrue(scrolledHeading.isHittable, "The detail keeps its scrolled section")
            XCTAssertFalse(app.staticTexts["detail-direction"].isHittable, "Resizing must not reset the detail to the top")
            capture("Window \(Int(width)) points selected and scrolled")
        }
        XCTAssertEqual(visibleListOrder().first, listAnchor,
                       "Collapsing and expanding must preserve the list position")
        let mapButton = app.buttons["show-route-map"]
        bringIntoView(mapButton, in: departureScroll, towardEnd: false)
        XCTAssertTrue(mapButton.isHittable)
        mapButton.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        for width in [375.0, 1200.0] {
            resizeWindow(width: width, height: 650)
            XCTAssertTrue(app.maps.firstMatch.isHittable)
            XCTAssertTrue(app.navigationBars["Walking route"].exists)
            capture("Window \(Int(width)) points with route sheet")
        }
        app.buttons["Done"].tap()
        XCTAssertTrue(detailTitle.exists)
    }

    func testCompactHeightScreensAndRotation() throws {
        try exerciseCompactHeight(largeText: false)
    }

    func testCompactHeightScreensAtLargestTextSize() throws {
        try exerciseCompactHeight(largeText: true)
    }

    private func exerciseCompactHeight(largeText: Bool) throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Phone rotation is checked on iPhone destinations") }
        XCUIDevice.shared.orientation = .landscapeLeft
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        launchAndAllowLocation()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertLessThanOrEqual(app.frame.height, 430)
        let suffix = largeText ? " accessibility" : ""
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 12))
        capture("Landscape nearby\(suffix)")
        app.buttons["departure-option"].firstMatch.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        let mapButton = app.buttons["show-route-map"]
        bringIntoView(mapButton, in: departureScroll)
        XCTAssertTrue(mapButton.isHittable)
        capture("Landscape detail\(suffix)")
        mapButton.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.maps.firstMatch.frame.height, 150)
        capture("Landscape route map\(suffix)")
        XCUIDevice.shared.orientation = .portrait
        wait(for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: app.maps.firstMatch)], timeout: 5)
        XCUIDevice.shared.orientation = .landscapeLeft
        wait(for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: app.maps.firstMatch)], timeout: 5)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["49 Hütteldorf"].exists)
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["Show nearby map"].tap()
        let pin = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'stop-map-pin' AND label BEGINSWITH 'Volkstheater,'")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        let card = app.scrollViews["selected-stop-card"]
        let showList = app.buttons["Show in list"]
        for _ in 0..<8 {
            if showList.isHittable && showList.frame.maxY <= card.frame.maxY { break }
            card.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(showList.isHittable)
        XCTAssertLessThanOrEqual(showList.frame.maxY, card.frame.maxY + 1)
        XCTAssertGreaterThan(app.maps.firstMatch.frame.height, 80)
        capture("Landscape selected stop\(suffix)")
        showList.tap()
        openAreaSearch()
        let query = app.textFields["area-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("Volkstheater")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        let result = app.buttons["area-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        capture("Landscape search\(suffix)")
        result.tap()
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 5))
    }

    private func resizeWindow(width: CGFloat, height: CGFloat) {
        for _ in 0..<3 {
            let size = app.frame.size
            if abs(size.width - width) < 10 && abs(size.height - height) < 10 { break }
            let window = app.windows.firstMatch
            let origin = window.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: size.width - 4, dy: size.height - 4))
                .press(forDuration: 0.1,
                       thenDragTo: origin.withOffset(CGVector(dx: (size.width + width) / 2 - 4,
                                                            dy: (size.height + height) / 2 - 4)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
            let settled = expectation(description: "Window resize animation settles")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
            wait(for: [settled], timeout: 2)
        }
        print("WINDOW requested=\(width)×\(height) actual=\(app.frame.size)")
        XCTAssertEqual(app.frame.width, width, accuracy: 10)
        XCTAssertEqual(app.frame.height, height, accuracy: 10)
    }

    func testExactWidthMatrixAndCompactHeight() throws {
        try exerciseSizeMatrix(largeText: false)
    }

    func testExactWidthMatrixAtLargestTextSize() throws {
        try exerciseSizeMatrix(largeText: true)
    }

    private func exerciseSizeMatrix(largeText: Bool) throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        server.setExtendedStops()
        app.launchEnvironment["DEPARTS_TEST_VIEWPORT"] = "1"
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        launchAndAllowLocation()
        guard UIDevice.current.userInterfaceIdiom == .pad,
              XCUIScreen.main.screenshot().image.size.width >= 1300 else {
            throw XCTSkip("Exact container widths through 1200 points use the 13-inch iPad destination")
        }
        let suffix = largeText ? " accessibility" : ""
        XCTAssertTrue(app.buttons["departure-option"].firstMatch.waitForExistence(timeout: 12))
        for width in [320, 402, 466, 669, 834, 1024, 1200] {
            setViewport(width: width, height: 700)
            XCTAssertTrue(nearbyList.exists)
            XCTAssertTrue(app.buttons["departure-option"].firstMatch.isHittable)
            capture("Matrix \(width) list\(suffix)")
        }
        setViewport(width: 320, height: 700)
        app.buttons["departure-option"].firstMatch.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        for width in [320, 402, 466, 669, 834, 1024, 1200, 320] {
            setViewport(width: width, height: 700)
            XCTAssertEqual(app.staticTexts["detail-direction"].label, "Hütteldorf")
            XCTAssertTrue(app.buttons["walking-directions"].exists)
            capture("Matrix \(width) detail\(suffix)")
        }
        setViewport(width: 320, height: 400)
        let scrolledHeading = departureScroll.staticTexts["Next departures"]
        bringIntoView(scrolledHeading, in: departureScroll)
        XCTAssertTrue(scrolledHeading.isHittable)
        XCTAssertFalse(app.staticTexts["detail-direction"].isHittable)
        let retainedOffset = scrolledHeading.frame.minY - departureScroll.frame.minY
        for width in [402, 466, 669, 834, 1024, 1200, 320] {
            setViewport(width: width, height: 400)
            capture("Matrix \(width) scrolled\(suffix)")
            let offset = scrolledHeading.frame.minY - departureScroll.frame.minY
            print("SCROLL width=\(width) headingOffset=\(offset) initialOffset=\(retainedOffset)")
            XCTAssertTrue(scrolledHeading.isHittable, "The scrolled section survives every exact width")
            // Reflow may shift the heading within its section. It must stay at
            // the same scrolled section, without returning to the service header.
            XCTAssertEqual(offset, retainedOffset, accuracy: 44, "Resizing keeps the detail's scroll anchor")
            let direction = app.staticTexts["detail-direction"]
            if direction.exists {
                let barBottom = app.navigationBars.allElementsBoundByIndex
                    .filter { $0.frame.intersects(departureScroll.frame) }.map { $0.frame.maxY }.max()!
                // XCUITest sometimes calls a lazy offscreen label hittable even
                // with a negative screen coordinate. Check its actual bounds.
                XCTAssertLessThanOrEqual(direction.frame.maxY, barBottom)
            }
        }
        capture("Matrix 320 retained scroll\(suffix)")
        setViewport(width: 669, height: 375)
        capture("Compact height before scrolling\(suffix)")
        XCTAssertTrue(app.buttons["walking-directions"].exists)
        let mapButton = app.buttons["show-route-map"]
        bringIntoView(mapButton, in: departureScroll, towardEnd: false)
        XCTAssertTrue(mapButton.isHittable)
        capture("Compact height detail\(suffix)")
        mapButton.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        setViewport(width: 320, height: 700)
        XCTAssertTrue(app.maps.firstMatch.isHittable)
        setViewport(width: 1200, height: 700)
        XCTAssertTrue(app.maps.firstMatch.isHittable, "A sheet stays open across compact and regular width")
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["detail-direction"].label, "Hütteldorf")
        setViewport(width: 320, height: 700)
        app.navigationBars.buttons["BackButton"].tap()
        setViewport(width: 1200, height: 700)
        let listAnchor = nearbyList.buttons.matching(NSPredicate(format: "identifier == 'departure-option' AND label CONTAINS 'from Second stop'")).firstMatch
        for _ in 0..<20 where !listAnchor.isHittable { nearbyList.swipeUp(velocity: .slow) }
        bringIntoView(listAnchor, in: nearbyList)
        XCTAssertTrue(listAnchor.isHittable)
        for width in [320, 1200, 320] {
            setViewport(width: width, height: 700)
            let top = app.navigationBars.allElementsBoundByIndex
                .filter { $0.frame.intersects(nearbyList.frame) }.map { $0.frame.maxY }.max()!
            XCTAssertGreaterThan(listAnchor.frame.maxY, top, "The scrolled list anchor remains visible")
            XCTAssertLessThan(listAnchor.frame.minY, nearbyList.frame.maxY)
        }
        capture("Matrix 320 retained list scroll\(suffix)")
        setViewport(width: 669, height: 375)
        capture("Compact height list\(suffix)")
        openAreaSearch()
        let query = app.textFields["area-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("Volkstheater")
        app.keyboards.buttons["Search"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        setViewport(width: 320, height: 700)
        XCTAssertEqual(query.value as? String, "Volkstheater")
        setViewport(width: 1200, height: 700)
        XCTAssertEqual(query.value as? String, "Volkstheater")
        capture("Matrix search retained\(suffix)")
        app.buttons["cancel-area-search"].tap()
    }

    private func setViewport(width: Int, height: Int) {
        server.setViewport(width: width, height: height)
        XCTAssertTrue(app.descendants(matching: .any)["layout-viewport"].waitForExistence(timeout: 3))
        let viewport = app.descendants(matching: .any)["layout-viewport"].firstMatch
        let resized = expectation(for: NSPredicate { _, _ in
            abs(viewport.frame.width - CGFloat(width)) < 1 && abs(viewport.frame.height - CGFloat(height)) < 1
        }, evaluatedWith: nil)
        wait(for: [resized], timeout: 5)
        print("CONTAINER requested=\(width)×\(height) actual=\(viewport.frame.size)")
        XCTAssertEqual(viewport.frame.width, CGFloat(width), accuracy: 1)
        XCTAssertEqual(viewport.frame.height, CGFloat(height), accuracy: 1)
    }

    private func openAreaSearch() {
        if app.buttons["choose-area"].isHittable { app.buttons["choose-area"].tap() }
        else {
            app.navigationBars.buttons.matching(NSPredicate(format: "label == 'More'")).firstMatch.tap()
            app.buttons["Choose area"].tap()
        }
    }

    private func bringIntoView(_ element: XCUIElement, in scroll: XCUIElement, towardEnd: Bool = true) {
        for _ in 0..<14 {
            let frame = scroll.frame
            let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.frame.intersects(frame) }
            let top = max(frame.minY + 8, (bars.map { $0.frame.maxY }.max() ?? frame.minY) + 8)
            let walking = app.buttons["walking-directions"]
            let bottom = walking.exists && walking.frame.minY > frame.midY
                ? min(frame.maxY - 8, walking.frame.minY - 12) : frame.maxY - 8
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let center = (top + bottom) / 2
            let delta = element.exists ? center - element.frame.midY : (towardEnd ? -1 : 1) * frame.height * 0.25
            let clamped = max(-frame.height * 0.25, min(frame.height * 0.25, delta))
            let origin = scroll.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: frame.width / 2, dy: center - frame.minY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: frame.width / 2, dy: center - frame.minY + clamped)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }

    #if PSEUDO_LOCALIZATION
    func testGermanRegionWithExpandedPseudoLocalization() {
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        launchAndAllowLocation()
        let row = app.buttons["departure-option"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        let status = app.staticTexts["board-status"].firstMatch
        print("PSEUDO context=\(status.label)")
        XCTAssertTrue(status.label.contains("400 m"))
        XCTAssertTrue(status.label.hasPrefix("［Im Umkreis"), "Verify the test-only German catalog is loaded")
        XCTAssertFalse(status.label.contains("$@"), "Interpolation must substitute every placeholder")
        XCTAssertFalse(row.label.contains("$@"))
        capture("German region expanded pseudo list")
        app.buttons["choose-area"].tap()
        XCTAssertTrue(app.textFields["area-query"].waitForExistence(timeout: 3))
        capture("German region expanded pseudo search")
        app.buttons["cancel-area-search"].tap()
        row.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        capture("German region expanded pseudo detail")
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        capture("German region expanded pseudo accessibility list")
        row.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
        capture("German region expanded pseudo accessibility detail")
        for _ in 0..<10 {
            let button = app.buttons["show-route-map"]
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = app.buttons["walking-directions"].frame.minY
            if button.isHittable && button.frame.minY > top && button.frame.maxY < bottom { break }
            let correction = min(0.25, max(-0.25, ((top + bottom) / 2 - button.frame.midY) / app.frame.height))
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + correction)),
                       withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        assertTarget(app.buttons["show-route-map"])
        XCTAssertGreaterThan(app.buttons["show-route-map"].frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThan(app.buttons["show-route-map"].frame.maxY, app.buttons["walking-directions"].frame.minY)
        capture("German region expanded pseudo accessibility advice")
        app.navigationBars.buttons.firstMatch.tap()
        if !app.buttons["choose-area"].isHittable {
            app.navigationBars.buttons.allElementsBoundByIndex.last!.tap()
            // Native overflow menu entries preserve the localized title, but
            // iOS 27 does not preserve a toolbar item's custom identifier here.
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'Chöösë árëá'")).firstMatch.tap()
        } else {
            app.buttons["choose-area"].tap()
        }
        XCTAssertTrue(app.textFields["area-query"].waitForExistence(timeout: 3))
        capture("German region expanded pseudo accessibility search")
    }
    #endif

    private var nearbyList: XCUIElement { app.collectionViews["nearby-list"] }
    private var departureScroll: XCUIElement { app.scrollViews["departure-detail"] }

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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
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

    private func visibleListOrder() -> [String] {
        nearbyList.buttons.matching(identifier: "departure-option").allElementsBoundByIndex.compactMap { row in
            guard row.isHittable, row.frame.minY > nearbyList.frame.minY + 90,
                  row.frame.maxY < nearbyList.frame.maxY,
                  let range = row.label.range(of: "(Tram|Bus|Subway|Train) .* toward .* from [^.]+", options: .regularExpression) else { return nil }
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
    private var viewport = ["width": 320, "height": 700]

    func setViewport(width: Int, height: Int) { queue.sync { viewport = ["width": width, "height": height] } }
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
        case "/test/viewport": return viewport
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
