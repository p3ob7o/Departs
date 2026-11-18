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
        XCTAssertEqual(app.navigationBars.count, 0, "Home has no bar: no title and no location button")
        XCTAssertFalse(app.buttons["locate"].exists)
        XCTAssertEqual(frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(frame.height, app.frame.width, accuracy: 1)
        XCTAssertEqual(frame.minY, topInset, accuracy: 1, "The square starts under the status bar")
        XCTAssertEqual(nearbyList.frame.minY, frame.maxY, accuracy: 1)
        let visible = rows.allElementsBoundByIndex.filter { nearbyList.frame.contains($0.frame) }
        print("HOME map=\(frame) list=\(nearbyList.frame) visibleRows=\(visible.count) firstRow=\(rows.firstMatch.frame)")
        XCTAssertGreaterThanOrEqual(visible.count, app.frame.height <= 667 ? 4 : 6)
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
        XCTAssertTrue(app.staticTexts["empty-departures"].waitForExistence(timeout: 10))
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

    func testHomeMapIgnoresDragAndPinchAndLabelsStillWork() {
        launch(); waitForRows()
        let label = mapLabel("Subway U3")
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        waitUntil { self.server.walkCount == 4 }
        let home = label.frame
        homeMap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: homeMap.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        homeMap.swipeLeft()
        homeMap.pinch(withScale: 2.5, velocity: 1)
        homeMap.pinch(withScale: 0.4, velocity: -1)
        homeMap.doubleTap()
        // Give any animation time to finish before measuring.
        let settle = expectation(description: "settle"); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settle.fulfill() }
        wait(for: [settle], timeout: 2)
        XCTAssertTrue(label.exists)
        XCTAssertEqual(label.frame.midX, home.midX, accuracy: 1, "A drag must not pan the home map")
        XCTAssertEqual(label.frame.midY, home.midY, accuracy: 1)
        XCTAssertEqual(label.frame.width, home.width, accuracy: 1, "A pinch must not zoom it")
        XCTAssertEqual(server.radii, [400])
        label.tap()
        waitUntil { label.isSelected }
        let single = mapLabel("Bus 48A")
        XCTAssertTrue(single.exists)
        single.tap()
        XCTAssertTrue(app.buttons["walking-directions"].waitForExistence(timeout: 5))
    }

    func testHomeMapFollowsASmallMoveWithoutLoadingStops() {
        launch(); waitForRows()
        waitUntil { self.server.walkCount == 4 }
        let label = mapLabel("Bus 48A")
        XCTAssertTrue(label.waitForExistence(timeout: 8))
        let before = label.frame, services = rowServices(), stops = server.radii.count
        // About 100 m north of the test coordinate.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 48.20134 + 100 / 111_200, longitude: 16.34941))
        let expected = 100 * app.frame.width / 960
        let started = Date()
        waitUntil(timeout: 5) { abs(label.frame.midY - before.midY - expected) < 4 }
        print("FOLLOW shift=\(label.frame.midY - before.midY) expected=\(expected) after=\(Date().timeIntervalSince(started))s")
        XCTAssertEqual(label.frame.midX, before.midX, accuracy: 2)
        XCTAssertEqual(server.radii.count, stops, "A move shorter than 150 m loads no stops")
        XCTAssertEqual(rowServices(), services, "The list stays put")
        capture("Home after a 100 m move")
    }

    func testStopNameLeavesWithItsLastLine() {
        launch(); waitForRows()
        waitUntil { self.server.walkCount == 4 }
        let list = nearbyList.frame
        // Two stops are both called Neubaugasse, so lines are matched by place:
        // a stop's lines are the rows between its name and the next name.
        let headers = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Siebensterngasse", "Burggasse/Neubaugasse", "Neubaugasse"]))
        var checkedAtTop = 0, pinnedWhilePassing = 0, pinnedY: CGFloat?, previous: CGFloat?
        // The header's area reaches below its text: measure the gap to the first line.
        let firstName = headers.matching(NSPredicate(format: "label == 'Siebensterngasse'")).firstMatch.frame
        let gap = rows.firstMatch.frame.minY - firstName.maxY
        XCTAssertGreaterThanOrEqual(gap, 0)
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
        launch(); waitForRows()
        waitUntil { self.server.walkCount == 4 }
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
        capture("Pinned stop name")
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
        XCTAssertEqual(homeMap.frame.minY, topInset, accuracy: 1)
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
        XCTAssertEqual(lineMap.frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(lineMap.frame.height, app.frame.width, accuracy: 1)
        XCTAssertEqual(lineMap.frame.minY, app.navigationBars.firstMatch.frame.maxY, accuracy: 1)
        XCTAssertEqual(app.navigationBars.count, 1, "The line screen keeps its bar")
        XCTAssertTrue(app.navigationBars.firstMatch.buttons["Back"].exists, app.navigationBars.firstMatch.debugDescription)
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
        // Maps plans a walk only with its own location permission. On a new
        // simulator grant it first: xcrun simctl privacy <id> grant location com.apple.Maps.
        // Granting it through the prompt makes iOS ask about Maps widgets later,
        // on top of whichever test is running.
        app.buttons["walking-directions"].tap()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 10))
        // A new simulator shows Maps' own first-run sheets, in an order that varies.
        for _ in 0..<4 {
            let prompts = ["Continue", "Not Now"].map { maps.buttons[$0].firstMatch }
            guard let prompt = prompts.first(where: { $0.waitForExistence(timeout: 1) }) else { break }
            prompt.tap()
        }
        // Maps 26 exposes a waypoint cell and a labeled segmented button;
        // Maps 27 exposes the destination and mode as identified buttons.
        let destination = maps.descendants(matching: .any).matching(NSPredicate(format:
            "(identifier == 'IconImage-WaypointNameText' OR identifier == 'RoutePlanningWaypointCell') AND label == 'Siebensterngasse'")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10), maps.debugDescription)
        let walk = maps.buttons.matching(NSPredicate(format: "identifier == 'WalkButton' OR label == 'Walk'")).firstMatch
        XCTAssertTrue(walk.waitForExistence(timeout: 5))
        waitUntil { walk.frame.width > 0 }
        XCTAssertTrue(walk.isSelected, "Apple Maps must open in walking mode")
        let safety = maps.alerts["Getting There Safely"]
        if safety.waitForExistence(timeout: 2) { safety.buttons["OK"].tap() }
        capture("Apple Maps walking destination")
        print("APPLE_MAPS walkingSelected=\(walk.isSelected) destination=\(destination.label)")
    }

    func testLineWithoutWalkingRouteStillShowsBothEndpoints() {
        server.setDirectionsFailed(true)
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
        XCTAssertGreaterThan(title.frame.height, 30)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX)
        capture("Line long destination")
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
    /// The status bar's height: home has no bar, so its map starts there.
    /// iPhone 17 Pro and the 667-point display measured 62 and 20 points.
    private var topInset: CGFloat { app.frame.height <= 667 ? 20 : 62 }
    /// The darkest grey level drawn inside a frame: a name's ink in light mode.
    private func darkestPixel(in frame: CGRect) -> Int {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
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
    /// Text as drawn on screen. A row's spoken label differs from what it shows.
    private func recognizedText() -> [String] {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return [] }
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
    private func launch(allowLocation: Bool = true) {
        app.launch()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        // A new simulator can also ask about Maps widgets, even with Maps'
        // location granted through simctl. Answer it and keep looking.
        for _ in 0..<2 where alert.waitForExistence(timeout: 5) {
            if alert.label.contains("widgets") || !alert.buttons["Allow While Using App"].exists {
                alert.buttons["Don’t Allow"].tap()
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
