import XCTest
@testable import Departs

final class FastDepartureTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private let coordinate = Coordinate(lat: 48.20134, lon: 16.34941)
    private let line = LineInfo(name: "49", direction: "Volkstheater", type: .tram)

    private func stop(_ id: String = "stop-1", lines: [LineInfo]? = nil) -> NearbyStop {
        .init(id: id, name: "Westbahnstraße", type: .tram, lines: lines ?? [line],
              location: .init(lat: 48.202, lon: 16.35), distance: 120)
    }
    private func departure(_ minutes: Double, live: Bool = true) -> Departure {
        .init(time: ISO8601DateFormatter().string(from: instant.addingTimeInterval(minutes * 60)),
              realTime: live, delay: nil, line: line)
    }
    private func route(_ seconds: Double = 180) -> WalkingRoute {
        .init(geometry: .init(type: "LineString", coordinates: [[16.34941, 48.20134], [16.35, 48.202]]),
              duration: seconds, distance: 220)
    }
    private func persistence() -> TransitPersistence {
        let suite = "departs.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return .init(defaults: defaults)
    }
    private func client() -> TransitClient {
        let stops = [stop()]; let departures = [departure(7), departure(12)]; let walk = route()
        return .init(stops: { _, _ in stops }, departures: { _ in departures }, directions: { _, _ in walk })
    }
    @MainActor private func makeStore(_ client: TransitClient? = nil, persistence storage: TransitPersistence? = nil) -> TransitStore {
        let date = instant
        return TransitStore(client: client ?? self.client(), persistence: storage ?? persistence(), now: { date })
    }
    private var fix: LocationFix { .init(coordinate: coordinate, capturedAt: instant, accuracy: 10) }
    private var area: SearchArea { .init(coordinate: coordinate, name: "Near you", source: .location) }

    @MainActor func testGroupedBoardAvoidsPerLineRequestAndFallsBackWhenUnsupported() async {
        var api = client()
        let line = self.line
        let departures = [departure(7)]
        var individualCalls = 0
        var groupedCalls = 0
        api.departures = { _ in individualCalls += 1; return departures }
        api.grouped = { _ in groupedCalls += 1; return GroupedDepartures(groups: [.init(line: line, departures: departures)]) }
        let store = makeStore(api)
        await store.loadArea(area)
        XCTAssertEqual(groupedCalls, 1)
        XCTAssertEqual(individualCalls, 0)
        XCTAssertEqual(store.runningIDs.count, 1)

        api.grouped = { _ in
            groupedCalls += 1
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Legacy array"))
        }
        let fallback = makeStore(api)
        await fallback.loadArea(area)
        await fallback.refreshAnswers(force: true)
        XCTAssertEqual(groupedCalls, 2, "Unsupported grouped responses are tried once per session")
        XCTAssertEqual(individualCalls, 2)
        XCTAssertEqual(fallback.runningIDs.count, 1)
    }

    @MainActor func testCompleteGroupedBoardMarksMissingLinesIdleWithoutExtraRequests() async {
        var api = client()
        let lines = [line, LineInfo(name: "N1", direction: "Night service", type: .bus)]
        let nearby = [stop(lines: lines)]
        let departures = [departure(7)]
        let line = self.line
        api.stops = { _, _ in nearby }
        api.grouped = { _ in .init(groups: [.init(line: line, departures: departures)], complete: true) }
        api.departures = { _ in XCTFail("Complete grouped boards must not fetch per line"); return [] }
        let store = makeStore(api)
        await store.loadArea(area)
        XCTAssertEqual(store.boards.count, 2)
        XCTAssertEqual(store.runningIDs.count, 1)
    }

    @MainActor func testCountdownDoesNotReorderAndInteractionDefersGroupChange() async {
        var current = instant
        var response = [departure(7)]
        var api = client()
        api.departures = { _ in response }
        let store = TransitStore(client: api, persistence: persistence(), now: { current })
        await store.loadArea(area)
        let original = store.runningIDs
        XCTAssertEqual(original.count, 1)
        current = instant.addingTimeInterval(900)
        _ = store.advice(for: stop().lineSelections[0], at: current)
        XCTAssertEqual(store.runningIDs, original, "A countdown tick must not move rows")
        store.interacting = true
        response = []
        await store.refreshBoard(stop().lineSelections[0], force: true)
        XCTAssertEqual(store.runningIDs, original)
        store.interacting = false
        XCTAssertTrue(store.runningIDs.isEmpty)
    }

    func testLeaveTimeSubtractsWalkingAndConservativeBuffer() {
        let board = DepartureBoard(departures: [departure(7)], checkedAt: instant)
        let walk = CachedWalk(origin: coordinate, route: route(), checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: walk, location: fix, now: instant)
        XCTAssertEqual(advice.title, "Leave in 2 min")
        XCTAssertEqual(advice.kind, .leave)
        XCTAssertTrue(advice.detail.contains("2 min buffer"))
    }

    func testEarlierTightDepartureUsesLaterReachableService() {
        let board = DepartureBoard(departures: [departure(1), departure(7)], checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: .init(origin: coordinate, route: route(), checkedAt: instant), location: fix, now: instant)
        XCTAssertEqual(advice.title, "Leave in 2 min")
        XCTAssertTrue(advice.detail.contains("Earlier departure is tight"))
    }

    func testAllTooSoonDoesNotTellUserToRun() {
        let board = DepartureBoard(departures: [departure(1), departure(3)], checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: .init(origin: coordinate, route: route(), checkedAt: instant), location: fix, now: instant)
        XCTAssertEqual(advice.kind, .caution)
        XCTAssertFalse(advice.title.contains("Leave"))
    }

    func testStaleOrFailedBoardNeverGivesLeaveAdvice() {
        let walk = CachedWalk(origin: coordinate, route: route(), checkedAt: instant)
        let old = DepartureBoard(departures: [departure(10)], checkedAt: instant.addingTimeInterval(-61))
        XCTAssertEqual(DepartureAdvice.make(board: old, walk: walk, location: fix, now: instant).kind, .unavailable)
        let fresh = DepartureBoard(departures: [departure(10)], checkedAt: instant)
        XCTAssertEqual(DepartureAdvice.make(board: fresh, walk: walk, location: fix, requestFailed: true, now: instant).kind, .unavailable)
    }

    func testUnknownOldOrApproximateLocationDoesNotGiveLeaveAdvice() {
        let board = DepartureBoard(departures: [departure(10)], checkedAt: instant)
        let walk = CachedWalk(origin: coordinate, route: route(), checkedAt: instant)
        let old = LocationFix(coordinate: coordinate, capturedAt: instant.addingTimeInterval(-121), accuracy: 10)
        let approximate = LocationFix(coordinate: coordinate, capturedAt: instant, accuracy: 500)
        for location in [nil, old, approximate] as [LocationFix?] {
            XCTAssertEqual(DepartureAdvice.make(board: board, walk: walk, location: location, now: instant).kind, .unavailable)
        }
    }

    func testWalkingRouteFromAnotherOriginCannotGiveAdvice() {
        let board = DepartureBoard(departures: [departure(10)], checkedAt: instant)
        let walk = CachedWalk(origin: .init(lat: 48.3, lon: 16.4), route: route(), checkedAt: instant)
        XCTAssertEqual(DepartureAdvice.make(board: board, walk: walk, location: fix, now: instant).kind, .unavailable)
    }

    func testScheduledAdviceIsExplicitAndWalkingMinutesRoundUp() {
        let board = DepartureBoard(departures: [departure(10, live: false)], checkedAt: instant)
        let walk = CachedWalk(origin: coordinate, route: route(181), checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: walk, location: fix, now: instant)
        XCTAssertTrue(advice.detail.contains("scheduled estimate"))
        XCTAssertEqual(walk.route.walkingMinutes, 4)
    }

    func testBoardExcludesExpiredAndInvalidTimesAndSortsUpcoming() {
        let invalid = Departure(time: "invalid", realTime: true, delay: nil)
        let board = DepartureBoard(departures: [departure(12), departure(-1), invalid, departure(3)], checkedAt: instant)
        XCTAssertEqual(board.upcoming(at: instant).map(\.time), [departure(3).time, departure(12).time])
    }

    func testFavoriteIdentitySurvivesProviderReorderingAndDuplicateLines() {
        let other = LineInfo(name: "49", direction: "Hütteldorf", type: .tram)
        let before = stop(lines: [line, other]).lineSelections[0]
        let after = stop(lines: [other, line]).lineSelections[1]
        XCTAssertEqual(before.id, after.id)
        XCTAssertEqual(stop(lines: [line, line, other]).lineSelections.count, 2)
    }

    @MainActor func testCacheAndPinsAreAvailableBeforeAnyNetworkCall() {
        let disk = persistence()
        let selection = stop().lineSelections[0]
        disk.saveNearby(.init(area: area, radius: 400, stops: [stop()], checkedAt: instant))
        disk.saveBoards([selection.id: .init(departures: [departure(7)], checkedAt: instant)])
        disk.savePins([selection])
        var calls = 0
        var api = client()
        api.stops = { _, _ in calls += 1; return [] }
        let store = makeStore(api, persistence: disk)
        XCTAssertEqual(store.stops.count, 1)
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 1)
        XCTAssertEqual(store.pins.map(\.id), [selection.id])
        XCTAssertEqual(calls, 0)
        XCTAssertNil(store.location)
        XCTAssertFalse(store.isBoardFresh(for: selection, at: instant))
        XCTAssertEqual(store.advice(for: selection, at: instant).kind, .unavailable)
    }

    @MainActor func testPinSurvivesRelaunchAndUnpinPersists() {
        let disk = persistence()
        let selection = stop().lineSelections[0]
        let store = makeStore(persistence: disk)
        store.togglePin(selection)
        let restored = makeStore(persistence: disk)
        XCTAssertTrue(restored.isPinned(selection))
        restored.togglePin(selection)
        XCTAssertTrue(makeStore(persistence: disk).pins.isEmpty)
    }

    @MainActor func testRestoredRecentBoardIsMarkedSavedUntilSuccessfullyRevalidated() async {
        let disk = persistence()
        let selection = stop().lineSelections[0]
        disk.saveBoards([selection.id: .init(departures: [departure(7)], checkedAt: instant)])
        let store = makeStore(persistence: disk)
        XCTAssertFalse(store.isBoardFresh(for: selection, at: instant))
        await store.refreshBoard(selection)
        XCTAssertTrue(store.isBoardFresh(for: selection, at: instant))
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 2)
    }

    @MainActor func testExplicitAreaRefreshDoesNotSkipRecentDepartureFetch() async {
        var calls = 0
        var api = client()
        let departures = [departure(7)]
        api.departures = { _ in calls += 1; return departures }
        let store = makeStore(api)
        await store.loadArea(area)
        await store.loadArea(area, forceRefresh: true)
        XCTAssertEqual(calls, 2)
    }

    @MainActor func testDeparturesPublishBeforeSlowDirectionsFinish() async {
        let routeStarted = expectation(description: "route started")
        var finishRoute: CheckedContinuation<WalkingRoute, Error>!
        var api = client()
        api.directions = { _, _ in
            try await withCheckedThrowingContinuation { continuation in
                finishRoute = continuation; routeStarted.fulfill()
            }
        }
        let store = makeStore(api)
        let selection = stop().lineSelections[0]
        let loading = Task { await store.updateLocation(fix) }
        await fulfillment(of: [routeStarted], timeout: 2)
        for _ in 0..<100 where store.boards[selection.id] == nil { await Task.yield() }
        XCTAssertNotNil(store.boards[selection.id])
        XCTAssertNil(store.walk(for: selection.stop, at: instant))
        finishRoute.resume(returning: route())
        await loading.value
        XCTAssertEqual(store.advice(for: selection, at: instant).title, "Leave in 2 min")
    }

    @MainActor func testFailedRefreshKeepsUsefulDataButDisablesAdvice() async {
        var fail = false
        var api = client()
        let departures = [departure(7)]
        api.departures = { _ in
            if fail { throw APIError.requestFailed }
            return departures
        }
        let store = makeStore(api)
        await store.updateLocation(fix)
        let selection = stop().lineSelections[0]
        XCTAssertEqual(store.advice(for: selection, at: instant).kind, .leave)
        fail = true
        await store.refreshSelection(selection, force: true)
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 1)
        XCTAssertTrue(store.boardErrors.contains(selection.id))
        XCTAssertEqual(store.advice(for: selection, at: instant).kind, .unavailable)
        XCTAssertFalse(store.loadingBoards.contains(selection.id))
    }

    @MainActor func testOlderAreaResponseCannotReplaceNewSearch() async {
        let started = expectation(description: "old area started")
        var finishOld: CheckedContinuation<[NearbyStop], Error>!
        let newest = stop("new")
        var api = client()
        api.stops = { coordinate, _ in
            if coordinate.lat == 48 {
                return try await withCheckedThrowingContinuation { finishOld = $0; started.fulfill() }
            }
            return [newest]
        }
        let store = makeStore(api)
        let old = Task { await store.loadArea(.init(coordinate: .init(lat: 48, lon: 16), name: "Old area", source: .chosen)) }
        await fulfillment(of: [started], timeout: 2)
        await store.loadArea(.init(coordinate: coordinate, name: "New area", source: .chosen))
        finishOld.resume(returning: [stop("old")])
        await old.value
        XCTAssertEqual(store.area?.name, "New area")
        XCTAssertEqual(store.stops.map(\.id), ["new"])
        XCTAssertFalse(store.isLoadingStops)
    }

    @MainActor func testBackgroundLocationDoesNotReplaceChosenArea() async {
        let store = makeStore()
        let chosen = SearchArea(coordinate: .init(lat: 52, lon: 13), name: "Berlin", source: .chosen)
        await store.loadArea(chosen)
        await store.updateLocation(fix)
        XCTAssertEqual(store.area, chosen)
        XCTAssertNotNil(store.location)
    }

    @MainActor func testSearchFartherIsExplicitAndBounded() async {
        var radii: [Int] = []
        var api = client()
        api.stops = { _, radius in radii.append(radius); return [] }
        let store = makeStore(api)
        await store.loadArea(area)
        await store.searchFarther()
        await store.searchFarther()
        await store.searchFarther()
        XCTAssertEqual(radii, [400, 800, 1600])
        XCTAssertFalse(store.canSearchFarther)
    }

    @MainActor func testConcurrentBoardLoadsCoalesceAndFreshDataIsReused() async {
        let started = expectation(description: "board started")
        var finish: CheckedContinuation<[Departure], Error>!
        var count = 0
        var api = client()
        api.departures = { _ in
            count += 1
            return try await withCheckedThrowingContinuation { finish = $0; started.fulfill() }
        }
        let store = makeStore(api)
        let selection = stop().lineSelections[0]
        let first = Task { await store.refreshBoard(selection) }
        await fulfillment(of: [started], timeout: 2)
        await store.refreshBoard(selection, force: true)
        XCTAssertEqual(count, 1)
        finish.resume(returning: [departure(7)])
        await first.value
        await store.refreshBoard(selection)
        XCTAssertEqual(count, 1)
    }

    @MainActor func testRefreshDoesNotFetchWalkingRouteAgainOrShuffleRows() async {
        var reversed = false
        var directionsCalls = 0
        let initial = [stop("a"), stop("b")]
        let walk = route()
        var api = client()
        api.stops = { _, _ in reversed ? initial.reversed() : initial }
        api.directions = { _, _ in directionsCalls += 1; return walk }
        let store = makeStore(api)
        await store.updateLocation(fix)
        XCTAssertEqual(directionsCalls, 2)
        reversed = true
        await store.loadArea(area)
        await store.refreshAnswers(force: true)
        XCTAssertEqual(store.stops.map(\.id), ["a", "b"])
        XCTAssertEqual(directionsCalls, 2)
    }

    @MainActor func testCancelledScreenCanStillCacheCompletedImmutableBoard() async {
        let started = expectation(description: "board started")
        var finish: CheckedContinuation<[Departure], Error>!
        var api = client()
        api.departures = { _ in try await withCheckedThrowingContinuation { finish = $0; started.fulfill() } }
        let store = makeStore(api)
        let selection = stop().lineSelections[0]
        let task = Task { await store.refreshBoard(selection) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        finish.resume(returning: [departure(7)])
        await task.value
        XCTAssertNotNil(store.boards[selection.id])
        XCTAssertFalse(store.boardErrors.contains(selection.id))
    }

    @MainActor func testFirstScreenLoadsOnlySixOptionsInBoundedBatches() async {
        let tracker = RequestTracker()
        let nearby = (0..<12).map { stop("stop-\($0)") }
        let departures = [departure(7)]
        var api = client()
        api.stops = { _, _ in nearby }
        api.departures = { _ in
            await tracker.begin()
            try await Task.sleep(for: .milliseconds(10))
            await tracker.end()
            return departures
        }
        let store = makeStore(api)
        await store.loadArea(area)
        let (count, peak) = await tracker.summary()
        XCTAssertEqual(count, 6, "Offscreen services should not cost a request")
        XCTAssertEqual(peak, 3, "A slow provider must not trigger an unbounded burst")
        XCTAssertEqual(store.boards.count, 6)
        store.showMore()
        await store.refreshAnswers()
        let (afterMore, _) = await tracker.summary()
        XCTAssertEqual(afterMore, 12)
    }

    @MainActor func testFailedWalkingDirectionsDoNotHideDepartures() async {
        var api = client()
        api.directions = { _, _ in throw APIError.requestFailed }
        let store = makeStore(api)
        await store.updateLocation(fix)
        let selection = stop().lineSelections[0]
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 2)
        XCTAssertNil(store.walk(for: selection.stop, at: instant))
        XCTAssertEqual(store.advice(for: selection, at: instant).kind, .unavailable)
        XCTAssertTrue(store.loadingWalks.isEmpty)
    }

    @MainActor func testLocationUpdateOnDetailDoesNotLoadHiddenNearbyBoards() async {
        var nearbyCalls = 0
        var requested: [String] = []
        let departures = [departure(7)]
        var api = client()
        api.stops = { _, _ in nearbyCalls += 1; return [] }
        api.departures = { selection in requested.append(selection.id); return departures }
        let store = makeStore(api)
        let selection = stop().lineSelections[0]
        await store.updateLocation(fix, showing: selection)
        XCTAssertEqual(nearbyCalls, 0)
        XCTAssertEqual(requested, [selection.id])
    }

    @MainActor func testPinnedLinkDecodesOpaqueIdentifierAndRejectsUnrelatedURL() {
        let id = stop().lineSelections[0].id
        var url = URLComponents()
        url.scheme = "departs"; url.host = "pin"
        url.queryItems = [URLQueryItem(name: "id", value: id)]
        XCTAssertEqual(RouteNavigation.pinID(from: url.url!), id)
        XCTAssertNil(RouteNavigation.pinID(from: URL(string: "https://example.com/pin?id=abc")!))
        XCTAssertNil(RouteNavigation.pinID(from: URL(string: "departs://pin?id=")!))
    }

    func testNearbyURLIncludesExplicitRadiusWithoutChangingHost() throws {
        let url = try APIService.nearbyStopsURL(lat: 48.2, lon: 16.3, radius: 800)
        XCTAssertEqual(url.host, "departs.vercel.app")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "radius" }?.value, "800")
    }
}

private actor RequestTracker {
    private var active = 0
    private var count = 0
    private var peak = 0
    func begin() { active += 1; count += 1; peak = max(peak, active) }
    func end() { active -= 1 }
    func summary() -> (Int, Int) { (count, peak) }
}
