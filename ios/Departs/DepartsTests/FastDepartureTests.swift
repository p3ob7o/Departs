import XCTest
import Observation
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

    @MainActor func testDetailAndMapUseTheListsMergedStopGroup() async {
        let secondLine = LineInfo(name: "50", direction: "Park", type: .tram)
        let platforms = [stop("a"), stop("b", lines: [line, secondLine])]
        var api = client()
        api.stops = { _, _ in platforms }
        let firstLine = line
        let times = [departure(7)]
        api.grouped = { _ in .init(groups: [.init(line: firstLine, departures: times)], complete: true) }
        let store = makeStore(api)
        await store.updateLocation(fix)
        let group = store.group(containing: platforms[1])
        XCTAssertEqual(store.groups.count, 1)
        XCTAssertEqual(group.id, store.groups[0].id)
        XCTAssertEqual(group.active.map(\.line.name), ["49", "49"])
        XCTAssertEqual(group.idle.map(\.line.name), ["50"])
        let marker = StopsMapView.StopAnnotation(group: group)
        XCTAssertEqual(marker.stopId, group.id)
        XCTAssertEqual(marker.badgeName, "49 +1", "Count distinct lines, not platforms or directions")
        XCTAssertTrue(marker.spokenLabel.contains("Tram 50"))
        XCTAssertEqual(marker.coordinate.latitude, platforms[0].location.lat, accuracy: 0.000001)
    }

    func testSkippedDepartureMarkersFollowAdviceAndDisappearWhenSaved() {
        let board = DepartureBoard(departures: [departure(3), departure(13)], checkedAt: instant)
        let walk = CachedWalk(origin: coordinate, route: route(), checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: walk, location: fix, now: instant)
        XCTAssertTrue(advice.isTooTight(board.departures[0]))
        XCTAssertFalse(advice.isTooTight(board.departures[1]))
        let saved = DepartureAdvice.make(board: board, walk: walk, location: fix, requestFailed: true, now: instant)
        XCTAssertFalse(saved.isTooTight(board.departures[0]))
    }

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
        XCTAssertEqual(store.groups.flatMap(\.active).count, 1)

        api.grouped = { _ in
            groupedCalls += 1
            throw APIError.groupedUnavailable
        }
        let fallback = makeStore(api)
        await fallback.loadArea(area)
        await fallback.refreshAnswers(force: true)
        XCTAssertEqual(groupedCalls, 2, "Unsupported grouped responses are tried once per session")
        XCTAssertEqual(individualCalls, 2)
        XCTAssertEqual(fallback.groups.flatMap(\.active).count, 1)
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
        XCTAssertEqual(store.groups.flatMap(\.active).count, 1)
    }

    @MainActor func testCountdownDoesNotReorderAndInteractionDefersGroupChange() async {
        var current = instant
        var response = [departure(7)]
        var api = client()
        api.departures = { _ in response }
        let store = TransitStore(client: api, persistence: persistence(), now: { current })
        await store.loadArea(area)
        let original = store.groups.flatMap(\.active).map(\.id)
        XCTAssertEqual(original.count, 1)
        current = instant.addingTimeInterval(900)
        _ = store.advice(for: stop().lineSelections[0], at: current)
        XCTAssertEqual(store.groups.flatMap(\.active).map(\.id), original, "A countdown tick must not move rows")
        store.interacting = true
        response = []
        await store.refreshBoard(stop().lineSelections[0], force: true)
        XCTAssertEqual(store.groups.flatMap(\.active).map(\.id), original)
        store.interacting = false
        XCTAssertTrue(store.groups.flatMap(\.active).isEmpty)
    }

    @MainActor func testPinsLoadFirstAndRefreshOnlyVisibleStopsWithRecencyThrottle() async {
        var time = instant
        let nearby = (0..<12).map { stop("s\($0)") }
        let disk = persistence()
        disk.savePins([nearby[9].lineSelections[0]])
        var requested: [String] = []
        var api = client()
        let line = self.line, departures = [departure(7)]
        api.stops = { _, _ in nearby }
        api.grouped = { id in requested.append(id); return .init(groups: [.init(line: line, departures: departures)], complete: true) }
        let store = TransitStore(client: api, persistence: disk, now: { time })
        await store.loadArea(area)
        XCTAssertTrue(requested.prefix(3).contains("s9"), "An offscreen nearby pin has opening priority")
        XCTAssertNotNil(store.boards[nearby[9].lineSelections[0].id])
        for stop in nearby {
            store.setVisible([stop], elementID: "row", visible: true)
            await store.refreshAnswers()
        }
        XCTAssertEqual(Set(requested).count, 12)
        requested = []
        await store.refreshAnswers()
        await store.updateLocation(fix)
        XCTAssertTrue(requested.isEmpty, "Location fixes and timer refreshes share a 25-second throttle")
        time.addTimeInterval(30)
        await store.refreshAnswers()
        XCTAssertEqual(Set(requested), ["s9", "s11"], "Scrolling through every stop must not enlarge periodic refresh")
        requested = []
        await store.refreshAnswers(force: true)
        XCTAssertEqual(Set(requested), ["s9", "s11"], "Explicit refresh bypasses recency, but not visibility")
    }

    @MainActor func testSavedHeaderKeepsItsStatusWhenItPushesEveryRowOffscreen() async {
        let disk = persistence()
        let stop = stop()
        let selected = stop.lineSelections[0]
        disk.saveNearby(.init(area: area, radius: 400, stops: [stop], checkedAt: instant))
        disk.saveBoards([selected.id: .init(departures: [departure(7)], checkedAt: instant)])
        let store = makeStore(persistence: disk)
        store.setVisible([stop], elementID: "row", visible: true)
        XCTAssertTrue(store.needsListRefresh(at: instant))
        store.setVisible([stop], elementID: "row", visible: false)
        XCTAssertTrue(store.needsListRefresh(at: instant), "An empty viewport is not evidence of fresh data")
        await store.refreshAnswers()
        XCTAssertFalse(store.needsListRefresh(at: instant), "Opening refresh must revalidate cached boards even with only the header visible")
    }

    @MainActor func testRepeatedVisibilityCallbacksDoNotRepublishTheList() async {
        let stop = stop()
        let store = makeStore()
        await store.loadArea(area)
        store.setVisible([stop], elementID: "row", visible: true)
        let changed = expectation(description: "Repeated visibility must not invalidate the list")
        changed.isInverted = true
        withObservationTracking {
            _ = store.displayedOptions
        } onChange: {
            changed.fulfill()
        }
        store.setVisible([stop], elementID: "row", visible: true)
        await fulfillment(of: [changed], timeout: 0.05)
    }

    @MainActor func testLegacyRefreshStaysBoundedAfterScrollingEveryStop() async {
        var time = instant
        let lines = [line, LineInfo(name: "50", direction: "Centre", type: .tram)]
        let nearby = (0..<12).map { stop("s\($0)", lines: lines) }
        let disk = persistence()
        disk.savePins([nearby[9].lineSelections[0]])
        var requested: [String] = []
        var api = client()
        let departures = [departure(7)]
        api.stops = { _, _ in nearby }
        api.departures = { selection in requested.append(selection.id); return departures }
        let store = TransitStore(client: api, persistence: disk, now: { time })
        await store.loadArea(area)
        XCTAssertEqual(requested.count, 8)
        for stop in nearby {
            store.setVisible([stop], elementID: "row", visible: true)
            await store.refreshAnswers()
        }
        XCTAssertEqual(requested.count, 24)
        requested = []
        time.addTimeInterval(30)
        await store.refreshAnswers()
        XCTAssertEqual(Set(requested), Set((nearby[9].lineSelections + nearby[11].lineSelections).map(\.id)))
        XCTAssertEqual(requested.count, 4, "Two visible/pinned stops, not all 24 previously seen routes")
        requested = []
        await store.updateLocation(fix)
        XCTAssertTrue(requested.isEmpty)
    }

    @MainActor func testLegacyFallbackReusesRecentIndividualBoardUnlessForced() async {
        var api = client()
        var calls = 0
        let departures = [departure(7)]
        api.departures = { _ in calls += 1; return departures }
        api.grouped = { _ in throw APIError.groupedUnavailable }
        let store = makeStore(api)
        await store.refreshBoard(stop().lineSelections[0])
        await store.loadArea(area)
        XCTAssertEqual(calls, 1, "A recent detail board must not be fetched again by legacy list fallback")
        await store.refreshAnswers(force: true)
        XCTAssertEqual(calls, 2)
    }

    @MainActor func testCallerCancellationDoesNotCancelSharedStopQueue() async {
        let started = expectation(description: "Grouped request started")
        var finish: CheckedContinuation<GroupedDepartures, Error>!
        var api = client()
        api.grouped = { _ in try await withCheckedThrowingContinuation { finish = $0; started.fulfill() } }
        let store = makeStore(api)
        let caller = Task { await store.loadArea(area) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(store.loadingBoards.contains(stop().lineSelections[0].id))
        caller.cancel()
        finish.resume(returning: .init(groups: [.init(line: line, departures: [departure(7)])], complete: true))
        await caller.value
        XCTAssertEqual(store.boards.count, 1)
        XCTAssertTrue(store.boardErrors.isEmpty)
        XCTAssertTrue(store.loadingBoards.isEmpty)
    }

    @MainActor func testCancelledStopCanBeRequestedAgain() async {
        var api = client()
        var calls = 0
        let line = self.line, departures = [departure(7)]
        api.grouped = { _ in
            calls += 1
            if calls == 1 { throw CancellationError() }
            return .init(groups: [.init(line: line, departures: departures)], complete: true)
        }
        let store = makeStore(api)
        await store.loadArea(area)
        XCTAssertTrue(store.boards.isEmpty)
        await store.loadGroup(store.groups[0])
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(store.boards.count, 1)
    }

    @MainActor func testGroupedFailureDoesNotFanOut() async {
        var api = client()
        api.departures = { _ in XCTFail("Only a confirmed legacy array may fan out"); return [] }
        api.grouped = { _ in throw APIError.requestFailed }
        let failed = makeStore(api)
        await failed.loadArea(area)
        XCTAssertTrue(failed.boards.isEmpty)
        XCTAssertEqual(failed.boardErrors.count, 1)
    }

    @MainActor func testCappedMissingLineIsCollapsedWithoutErrorsOrRefreshPrompt() async {
        let lines = [line, LineInfo(name: "N1", direction: "Night service", type: .bus)]
        let nearby = stop(lines: lines), departures = [departure(7)], line = self.line
        var complete = false
        var api = client()
        api.stops = { _, _ in [nearby] }
        api.departures = { _ in XCTFail("A filtered call cannot recover a capped board"); return [] }
        api.grouped = { _ in .init(groups: [.init(line: line, departures: departures)], complete: complete) }
        let capped = makeStore(api)
        await capped.loadArea(area)
        let limited = nearby.lineSelections[1]
        XCTAssertTrue(capped.boardErrors.isEmpty)
        XCTAssertFalse(capped.needsListRefresh(at: instant))
        XCTAssertEqual(capped.groups[0].active.count, 1)
        XCTAssertEqual(capped.groups[0].idle.map(\.id), [limited.id])
        XCTAssertEqual(capped.boards[limited.id]?.coverageLimit?.before, departure(7).time)
        let row = DepartureRowContent(board: capped.boards[limited.id], advice: capped.advice(for: limited, at: instant),
                                      loading: false, failed: false, fresh: true, idle: true, now: instant)
        XCTAssertEqual(row.answer, "No departure listed before \(TimeFormatter.formatTime(departure(7).time))")
        XCTAssertFalse(row.status.contains("retry"))
        await capped.refreshSelection(limited, force: true)
        XCTAssertNotNil(capped.boards[limited.id]?.coverageLimit, "Detail refresh must retain the coverage bound")
        complete = true
        await capped.refreshAnswers(force: true)
        XCTAssertNil(capped.boards[limited.id]?.coverageLimit)
        XCTAssertTrue(capped.boards[limited.id]?.departures.isEmpty == true)
    }

    func testCoverageLimitKeepsOlderSavedBoardsDecodable() throws {
        let old = try JSONDecoder().decode(DepartureBoard.self, from: Data("{\"departures\":[],\"checkedAt\":0}".utf8))
        XCTAssertNil(old.coverageLimit)
        let limited = DepartureBoard(departures: [], checkedAt: instant, coverageLimit: .init(before: departure(7).time))
        let restored = try JSONDecoder().decode(DepartureBoard.self, from: JSONEncoder().encode(limited))
        XCTAssertEqual(restored.coverageLimit?.before, limited.coverageLimit?.before)
    }

    @MainActor func testArrivalDuringInteractionKeepsWholePartitionUntilScrollEnds() async {
        let started = expectation(description: "Board in flight")
        var finish: CheckedContinuation<GroupedDepartures, Error>!
        var api = client()
        api.grouped = { _ in try await withCheckedThrowingContinuation { finish = $0; started.fulfill() } }
        let store = makeStore(api)
        let loading = Task { await store.loadArea(area) }
        await fulfillment(of: [started], timeout: 2)
        let before = store.groups[0].active.map(\.id)
        store.interacting = true
        finish.resume(returning: .init(groups: [], complete: true))
        await loading.value
        XCTAssertNotNil(store.boards[before[0]])
        XCTAssertEqual(store.groups[0].active.map(\.id), before)
        XCTAssertTrue(store.groups[0].idle.isEmpty)
        store.interacting = false
        XCTAssertTrue(store.groups[0].active.isEmpty)
        XCTAssertEqual(store.groups[0].idle.map(\.id), before)
    }

    @MainActor func testHorizonAndProviderOrderChangeOnlyOnBoardArrival() async {
        var time = instant
        let lines = (0..<4).map { LineInfo(name: "L\($0)", direction: "City \($0)", type: .bus) }
        let first = NearbyStop(id: "a", name: "A", type: .bus, lines: lines, location: coordinate, distance: 10)
        let last = NearbyStop(id: "c", name: "C", type: .bus, lines: [line], location: stop().location, distance: 50)
        var api = client()
        var responses = [GroupedDepartures.Group(line: lines[0], departures: [departure(59)]),
                         .init(line: lines[1], departures: [departure(60)]),
                         .init(line: lines[2], departures: [departure(61)]),
                         .init(line: lines[3], departures: [])]
        api.stops = { _, _ in [first, last] }
        api.grouped = { _ in .init(groups: responses, complete: true) }
        let store = TransitStore(client: api, persistence: persistence(), now: { time })
        await store.loadArea(area)
        XCTAssertEqual(store.groups.map(\.id), ["a", "c"])
        XCTAssertEqual(store.groups[0].active.map(\.line.name), ["L0", "L1"])
        XCTAssertEqual(store.groups[0].idle.map(\.line.name), ["L2", "L3"])
        time.addTimeInterval(120)
        _ = store.advice(for: first.lineSelections[2], at: time)
        XCTAssertEqual(store.groups[0].idle.map(\.line.name), ["L2", "L3"], "Countdown crossing the horizon cannot reorder")
        responses = [.init(line: lines[3], departures: [departure(10)])]
        await store.refreshAnswers(force: true)
        XCTAssertEqual(store.groups[0].active.map(\.line.name), ["L3"])
        XCTAssertEqual(store.groups.map(\.id), ["a", "c"])
    }

    @MainActor func testMoreThanEightyBoardsSurviveOpeningDetail() async {
        let lines = (0..<90).map { LineInfo(name: "L\($0)", direction: "Centre", type: .bus) }
        var api = client()
        let nearby = stop(lines: lines), departures = [departure(7)]
        api.stops = { _, _ in [nearby] }
        api.grouped = { _ in .init(groups: lines.map { .init(line: $0, departures: departures) }, complete: true) }
        let disk = persistence(), store = makeStore(api, persistence: nil)
        await store.loadArea(area)
        await store.refreshSelection(nearby.lineSelections.last!, force: true)
        XCTAssertEqual(store.boards.count, 90)
        disk.saveBoards(store.boards)
        XCTAssertEqual(disk.loadBoards().count, 40)
    }

    func testCompactContentDistinguishesUnknownEmptySavedAndFuture() {
        let unavailable = DepartureAdvice(title: "", detail: "", kind: .unavailable)
        func content(_ board: DepartureBoard?, fresh: Bool = true, idle: Bool = false) -> DepartureRowContent {
            .init(board: board, advice: unavailable, loading: false, failed: false, fresh: fresh, idle: idle, now: instant)
        }
        XCTAssertEqual(content(nil).answer, "Unavailable")
        XCTAssertEqual(content(.init(departures: [], checkedAt: instant)).answer, "Nothing soon")
        let saved = content(.init(departures: [departure(7), departure(12)], checkedAt: instant), fresh: false)
        XCTAssertEqual(saved.times.count, 1)
        XCTAssertFalse(saved.times.contains { $0.text == saved.answer })
        XCTAssertEqual(saved.status, "Saved information")
        let future = content(.init(departures: [departure(166)], checkedAt: instant), idle: true)
        XCTAssertEqual(future.answer, TimeFormatter.formatTime(departure(166).time))
        XCTAssertFalse(future.answer.contains("Leave"))
    }

    func testCompactAdviceNamesItsDepartureAndOnlyShowsWholeMinuteDelays() {
        let first = Departure(time: departure(1).time, realTime: true, delay: 5)
        let board = DepartureBoard(departures: [first, departure(7)], checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: .init(origin: coordinate, route: route(), checkedAt: instant), location: fix, now: instant)
        let content = DepartureRowContent(board: board, advice: advice, loading: false, failed: false, fresh: true, idle: false, now: instant)
        XCTAssertTrue(content.times[0].tooTight)
        XCTAssertEqual(content.times[1].text, "for \(TimeFormatter.formatTime(departure(7).time))")
        XCTAssertTrue(content.spokenTimes.contains("too tight"))
        XCTAssertFalse(content.status.contains("late"))
    }

    @MainActor func testDisplayOnlyPrefixUsesThreeDistinctSharedDirections() {
        let directions = ["Paris Nord", "Paris Sud", "Paris Est"]
        XCTAssertEqual(NearbyStopsView.displayDirection("Paris Nord", among: directions), "Nord")
        XCTAssertEqual(NearbyStopsView.displayDirection("Paris Nord", among: Array(directions.prefix(2))), "Paris Nord")
        XCTAssertEqual(NearbyStopsView.displayDirection("Paris Nord", among: directions + ["Lyon Centre"]), "Paris Nord")
    }

    @MainActor func testRecentAreasKeepFiveUniqueChoicesAcrossRelaunch() async {
        let storage = persistence()
        let store = makeStore(persistence: storage)
        for index in 0..<7 {
            await store.loadArea(.init(coordinate: coordinate, name: "Place \(index)", source: .chosen))
        }
        await store.loadArea(.init(coordinate: coordinate, name: "Place 4", source: .chosen))
        await store.loadArea(area)
        let restored = makeStore(persistence: storage)
        XCTAssertEqual(restored.recentAreas.map(\.name), ["Place 4", "Place 6", "Place 5", "Place 3", "Place 2"])
    }

    @MainActor func testSearchPromotesTransitWithoutReorderingEqualCategories() {
        let places = [false, true, false, true].enumerated().map { index, transit in
            PlaceResult(id: "\(index)", name: "Place \(index)", subtitle: "", coordinate: coordinate, transit: transit)
        }
        XCTAssertEqual(AreaSearchModel.transitFirst(places).map(\.id), ["1", "3", "0", "2"])
    }

    @MainActor func testChosenAreaRestoresWithoutFollowingDevice() async {
        let storage = persistence()
        let store = makeStore(persistence: storage)
        let chosen = SearchArea(coordinate: coordinate, name: "Chosen place", source: .chosen)
        await store.loadArea(chosen)
        let restored = makeStore(persistence: storage)
        XCTAssertEqual(restored.area, chosen)
        XCTAssertFalse(restored.followsLocation)
    }

    func testLeaveTimeSubtractsWalkingAndConservativeBuffer() {
        let board = DepartureBoard(departures: [departure(7)], checkedAt: instant)
        let walk = CachedWalk(origin: coordinate, route: route(), checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: walk, location: fix, now: instant)
        XCTAssertEqual(advice.title, "Leave in 2 min")
        XCTAssertEqual(advice.kind, .leave)
        XCTAssertTrue(advice.detail.contains("Includes 2 min extra"))
    }

    func testEarlierTightDepartureUsesLaterReachableService() {
        let board = DepartureBoard(departures: [departure(1), departure(7)], checkedAt: instant)
        let advice = DepartureAdvice.make(board: board, walk: .init(origin: coordinate, route: route(), checkedAt: instant), location: fix, now: instant)
        XCTAssertEqual(advice.title, "Leave in 2 min")
        XCTAssertTrue(advice.isTooTight(board.departures[0]))
        XCTAssertEqual(advice.departureTime, board.departures[1].time)
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
        XCTAssertTrue(advice.detail.contains("scheduled arrival"))
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

    @MainActor func testFirstScreenLoadsOnlyThreeStopsInBoundedBatches() async {
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
        XCTAssertEqual(count, 3, "Offscreen stops should not cost a request")
        XCTAssertEqual(peak, 3, "A slow provider must not trigger an unbounded burst")
        XCTAssertEqual(store.boards.count, 3)
        store.setVisible([nearby[6]], elementID: "visible", visible: true)
        await store.refreshAnswers()
        let (afterMore, _) = await tracker.summary()
        XCTAssertEqual(afterMore, 4)
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
