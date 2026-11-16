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
        let fetchedAt = instant.ISO8601Format()
        return .init(stops: { _, _ in stops }, departures: { _ in departures }, directions: { _, _ in walk },
                     batch: { ids in .init(fetchedAt: fetchedAt, boards: ids.map {
                         .init(stopId: $0, groups: [.init(line: stops[0].lines[0], departures: departures)])
                     }, missing: []) })
    }
    @MainActor private func makeStore(_ client: TransitClient? = nil, persistence storage: TransitPersistence? = nil) -> TransitStore {
        let date = instant
        return TransitStore(client: client ?? self.client(), persistence: storage ?? persistence(), now: { date })
    }
    private var fix: LocationFix { .init(coordinate: coordinate, capturedAt: instant, accuracy: 10) }
    private var area: SearchArea { .init(coordinate: coordinate, name: "Near you", source: .location) }

    private func sampleStops() throws -> [NearbyStop] {
        try JSONDecoder().decode([NearbyStop].self, from: JSONSerialization.data(withJSONObject: TransitSample.stops))
    }
    private func sampleBatch(at date: Date? = nil, missing: Set<String> = [], empty: Bool = false, changed: Bool = false) throws -> BatchDepartures {
        try JSONDecoder().decode(BatchDepartures.self, from: JSONSerialization.data(withJSONObject:
            TransitSample.batch(at: date ?? instant, missing: missing, empty: empty, changed: changed)))
    }
    private func sampleClient() throws -> TransitClient {
        var api = client()
        let stops = try sampleStops(), response = try sampleBatch()
        api.stops = { _, _ in stops }
        api.batch = { _ in response }
        return api
    }
    private func snapshot(_ stops: [NearbyStop], boards: [BatchDepartures.Board], pins: [StopLineSelection] = []) -> HomeSnapshot {
        .make(stops: stops, origin: coordinate, pins: pins,
              response: .init(fetchedAt: instant.ISO8601Format(), boards: boards, missing: []), checkedAt: instant)
    }
    private func service(_ name: String, _ destination: String) -> LineInfo { .init(name: name, direction: destination, type: .bus) }
    private func platform(_ id: String, meters: Double) -> NearbyStop {
        .init(id: id, name: id, type: .bus, lines: [],
              location: .init(lat: coordinate.lat + meters / 111_200, lon: coordinate.lon), distance: nil)
    }
    private func returned(_ stop: NearbyStop, _ services: [LineInfo]) -> BatchDepartures.Board {
        .init(stopId: stop.id, groups: services.map { .init(line: $0, departures: [departure(3), departure(9)]) })
    }

    func testViennaSeventeenPlatformsSelectExactlyEightRows() throws {
        let result = HomeSnapshot.make(stops: try sampleStops(), origin: coordinate, pins: [], response: try sampleBatch(), checkedAt: instant)
        XCTAssertEqual(result.groups.map(\.name), ["Siebensterngasse", "Burggasse/Neubaugasse", "Neubaugasse", "Neubaugasse"])
        XCTAssertEqual(result.groups.map { $0.active.count }, [4, 1, 1, 2])
        XCTAssertEqual(result.selections.map { "\($0.line.name) \($0.line.direction)" }, [
            "13A Wien Skodagasse", "13A Wien Hauptbahnhof", "49 Wien Parlament/Volkstheater",
            "49 Wien Hütteldorf, Bujattigasse", "48A Wien Parlament/Volkstheater", "14A Wien Reumannplatz",
            "U3 Wien Simmering", "U3 Wien Ottakring"])
        XCTAssertEqual(Set(result.selections.map { $0.line.serviceIdentity }).count, 8)
        for (group, baseline) in zip(result.groups, [29.0, 286, 312, 325]) {
            XCTAssertEqual(group.distance(from: coordinate), baseline, accuracy: 1.5)
        }
    }

    func testOneWayPairAddsOnlyOneDifferentDestinationAtSecondStop() {
        let a = platform("A", meters: 10), b = platform("B", meters: 80), c = platform("C", meters: 160)
        let result = snapshot([c, a, b], boards: [returned(a, [service("1", "North")]),
            returned(b, [service("1", "North"), service("1", "South"), service("1", "Depot")]),
            returned(c, [service("1", "East")])])
        XCTAssertEqual(result.groups.map(\.id), ["A", "B"])
        XCTAssertEqual(result.selections.map { $0.line.direction }, ["North", "South"])
    }

    func testThreeDestinationsAtNearestStopAreAllKeptAndNoFartherStopIsAdded() {
        let a = platform("A", meters: 10), b = platform("B", meters: 80)
        let result = snapshot([b, a], boards: [returned(a, [service("1", "North"), service("1", "South"), service("1", "Depot")]),
            returned(b, [service("1", "East")])])
        XCTAssertEqual(result.groups.map(\.id), ["A"])
        XCTAssertEqual(result.selections.map { $0.line.direction }, ["North", "South", "Depot"])
    }

    func testPinnedDestinationIsNeverRepeatedAndDoesNotPromoteAThirdDestination() throws {
        let stops = try sampleStops(), response = try sampleBatch()
        let original = HomeSnapshot.make(stops: stops, origin: coordinate, pins: [], response: response, checkedAt: instant)
        let pin = original.selections[0]
        let result = HomeSnapshot.make(stops: stops, origin: coordinate, pins: [pin], response: response, checkedAt: instant)
        XCTAssertEqual(result.pins.map(\.id), [pin.id])
        XCTAssertEqual(result.selections.count, 8)
        XCTAssertEqual(result.groups[0].active.count, 3)
        XCTAssertEqual(result.selections.filter { $0.line.name == "13A" }.count, 2)
    }

    func testCandidatesComeFromDeparturesEvenWhenStopHasNoLineMetadata() {
        let a = platform("A", meters: 10)
        XCTAssertTrue(a.lines.isEmpty)
        let result = snapshot([a], boards: [returned(a, [service("13A", "Main station")])])
        XCTAssertEqual(result.selections.map { $0.line.name }, ["13A"])
    }

    func testDuplicateStoredPinsShowOnceWithoutChangingTheirStableIdentities() throws {
        let stops = try sampleStops(), response = try sampleBatch()
        let first = StopLineSelection(stop: stops[0], line: response.boards[0].groups[0].line, lineIndex: 0)
        let second = StopLineSelection(stop: stops[6], line: first.line, lineIndex: 0)
        let result = HomeSnapshot.make(stops: stops, origin: coordinate, pins: [second, first], response: response, checkedAt: instant)
        XCTAssertEqual(result.pins.map(\.id), [second.id], "The first pin keeps its chosen platform")
        XCTAssertEqual(result.selections.count, 8)
        XCTAssertEqual(Set(result.selections.map { $0.line.serviceIdentity }).count, 8)
        XCTAssertNotEqual(first.id, second.id, "Stored pin links remain platform-specific")
    }

    func testSameNameWithin150MetersMergesAndUsesNearestEligiblePlatform() {
        let a = platform("A", meters: 20), b = NearbyStop(id: "B", name: "A", type: .bus, lines: [],
            location: platform("B", meters: 70).location, distance: nil)
        let result = snapshot([b, a], boards: [returned(b, [service("1", "North")]), returned(a, [service("1", "North")])])
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.selections.first?.stop.id, "A")
        XCTAssertEqual(result.groups.first?.nearestPlatform(to: coordinate)?.id, "A")
    }

    @MainActor func testRadiusAndHorizonExcludeOutsideExpiredAndFarFutureDepartures() async {
        let inside = platform("inside", meters: 20), outside = platform("outside", meters: 410)
        let values = [-1.0, 0, 60, 60.1, 166]
        let groups = values.enumerated().map { index, minutes in
            GroupedDepartures.Group(line: service("\(index)", "End"), departures: [departure(minutes)])
        }
        var api = client()
        api.stops = { _, _ in [inside, outside] }
        let response = BatchDepartures(fetchedAt: instant.ISO8601Format(), boards: [.init(stopId: inside.id, groups: groups)], missing: [])
        api.batch = { ids in XCTAssertEqual(ids, [inside.id]); return response }
        let store = makeStore(api)
        await store.loadArea(area)
        XCTAssertEqual(store.displayedOptions.map(\.line.name), ["1", "2"])
        XCTAssertEqual(store.stops.map(\.id), [inside.id])
    }

    @MainActor func testOpeningUsesOneBatchAndFourWalksThenOneBatchPerRefresh() async throws {
        var api = try sampleClient(), stopCalls = 0, batchCalls = 0, walkCalls = 0, detailCalls = 0
        let stops = try sampleStops(), response = try sampleBatch(), route = route()
        let walks = expectation(description: "one route per listed physical stop"); walks.expectedFulfillmentCount = 4
        api.stops = { _, _ in stopCalls += 1; return stops }
        api.batch = { ids in batchCalls += 1; XCTAssertEqual(ids.count, 17); return response }
        api.departures = { _ in detailCalls += 1; return [] }
        api.directions = { _, _ in walkCalls += 1; walks.fulfill(); return route }
        let store = makeStore(api)
        await store.updateLocation(fix)
        await fulfillment(of: [walks], timeout: 2)
        await store.refreshAnswers()
        XCTAssertEqual(stopCalls, 1); XCTAssertEqual(batchCalls, 1); XCTAssertEqual(walkCalls, 4); XCTAssertEqual(detailCalls, 0)
        await store.refreshAnswers(force: true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(batchCalls, 2); XCTAssertEqual(walkCalls, 4); XCTAssertEqual(detailCalls, 0)
        XCTAssertEqual(store.groups.map { $0.active.count }, [4, 1, 1, 2])
    }

    @MainActor func testFailedBatchKeepsEveryRowAndTimeButUsesClockWithoutFanout() async throws {
        var api = try sampleClient(), failed = false, individualCalls = 0
        let response = try sampleBatch()
        api.batch = { _ in if failed { throw APIError.requestFailed }; return response }
        api.departures = { _ in individualCalls += 1; return [] }
        let store = makeStore(api)
        await store.loadArea(area)
        let selections = store.displayedOptions, times = selections.map { store.home.boards[$0.id]!.departures.map(\.time) }
        failed = true
        await store.refreshAnswers(force: true)
        XCTAssertEqual(store.displayedOptions.map(\.id), selections.map(\.id))
        XCTAssertEqual(store.displayedOptions.map { store.home.boards[$0.id]!.departures.map(\.time) }, times)
        XCTAssertTrue(store.needsListRefresh(at: instant))
        for selection in selections {
            XCTAssertFalse(store.isHomeBoardFresh(for: selection, at: instant))
            let content = HomeRowContent(board: store.home.boards[selection.id], fresh: false, pinned: false, now: instant)
            XCTAssertFalse(content.answer.hasPrefix("In "))
            XCTAssertEqual(content.answer, TimeFormatter.formatTime(store.home.boards[selection.id]!.departures[0].time))
        }
        XCTAssertEqual(individualCalls, 0)
        failed = false
        await store.refreshAnswers(force: true)
        XCTAssertFalse(store.needsListRefresh(at: instant))
    }

    @MainActor func testPartialRefreshRetainsOrderAndNeverPromotesHiddenLines() async throws {
        var response = try sampleBatch()
        var api = try sampleClient()
        api.batch = { _ in response }
        let store = makeStore(api)
        await store.loadArea(area)
        let before = store.displayedOptions.map(\.id)
        response = try sampleBatch(missing: ["77704_312"], changed: true)
        await store.refreshAnswers(force: true)
        XCTAssertEqual(store.displayedOptions.map(\.id), before)
        XCTAssertFalse(store.isHomeBoardFresh(for: store.displayedOptions[0], at: instant))
        XCTAssertTrue(store.isHomeBoardFresh(for: store.displayedOptions[1], at: instant))
        XCTAssertTrue(store.home.missing.contains("77704_312"))
        XCTAssertTrue(store.needsListRefresh(at: instant))
    }

    @MainActor func testInitialMissingPlatformsHaveOneErrorPerPhysicalStopNotPerLine() async throws {
        let response = try sampleBatch(missing: ["77704_312", "77704_313", "77704_311", "77704_310"])
        var api = try sampleClient(); api.batch = { _ in response }
        let store = makeStore(api)
        await store.loadArea(area)
        XCTAssertEqual(store.groups.filter(\.hasMissingBoard).count, 1)
        XCTAssertEqual(store.groups.first?.name, "Siebensterngasse")
        XCTAssertTrue(store.groups.first!.active.isEmpty)
    }

    @MainActor func testProviderTimestampIncludesCDNAgeInFreshness() async throws {
        let response = try sampleBatch(at: instant.addingTimeInterval(-30))
        var api = try sampleClient(); api.batch = { _ in response }
        let store = makeStore(api)
        await store.loadArea(area)
        let selection = store.displayedOptions[0]
        XCTAssertTrue(store.isHomeBoardFresh(for: selection, at: instant))
        XCTAssertFalse(store.isHomeBoardFresh(for: selection, at: instant.addingTimeInterval(31)))
        XCTAssertEqual(store.home.boards[selection.id]?.checkedAt, instant.addingTimeInterval(-30))
    }

    @MainActor func testRelaunchShowsExactSavedListImmediatelyUntilRevalidation() async throws {
        let disk = persistence(), api = try sampleClient()
        let first = makeStore(api, persistence: disk)
        await first.loadArea(area)
        first.togglePin(first.displayedOptions[0])
        let savedIDs = first.displayedOptions.map(\.id)
        let restored = makeStore(api, persistence: disk)
        XCTAssertEqual(restored.displayedOptions.map(\.id), savedIDs)
        XCTAssertEqual(restored.displayedOptions.count, 8)
        XCTAssertTrue(restored.needsListRefresh(at: instant))
        XCTAssertTrue(restored.displayedOptions.allSatisfy { !restored.isHomeBoardFresh(for: $0, at: instant) })
        await restored.refreshAnswers()
        XCTAssertFalse(restored.needsListRefresh(at: instant))
    }

    @MainActor func testCountdownCannotChangeRowsAndScrollDefersTheWholeSnapshot() async throws {
        var response = try sampleBatch(), time = instant
        var api = try sampleClient(); api.batch = { _ in response }
        let store = TransitStore(client: api, persistence: persistence(), now: { time })
        await store.loadArea(area)
        let before = store.displayedOptions.map(\.id), firstTime = store.home.boards[before[0]]!.departures[0].time
        time.addTimeInterval(1800)
        for selection in store.displayedOptions {
            _ = HomeRowContent(board: store.home.boards[selection.id], fresh: store.isHomeBoardFresh(for: selection, at: time), pinned: false, now: time)
        }
        XCTAssertEqual(store.displayedOptions.map(\.id), before)
        store.setInteracting(true, presentationID: "list")
        response = try sampleBatch(at: time, changed: true)
        await store.refreshAnswers(force: true)
        XCTAssertEqual(store.displayedOptions.map(\.id), before)
        XCTAssertEqual(store.home.boards[before[0]]!.departures[0].time, firstTime)
        store.setInteracting(false, presentationID: "list")
        XCTAssertNotEqual(store.displayedOptions.map(\.id), before)
        XCTAssertEqual(store.displayedOptions[0].line.name, "99A")
    }

    @MainActor func testCallerCancellationDoesNotCancelOrDuplicateSharedBatch() async throws {
        var api = try sampleClient(), calls = 0
        let begun = expectation(description: "batch begun"), response = try sampleBatch()
        var finish: CheckedContinuation<BatchDepartures, Error>!
        api.batch = { _ in calls += 1; return try await withCheckedThrowingContinuation { finish = $0; begun.fulfill() } }
        let store = makeStore(api)
        let first = Task { await store.loadArea(area) }
        await fulfillment(of: [begun], timeout: 2)
        first.cancel()
        let second = Task { await store.refreshAnswers(force: true) }
        await Task.yield()
        XCTAssertEqual(calls, 1)
        finish.resume(returning: response)
        await first.value; await second.value
        XCTAssertEqual(store.displayedOptions.count, 8)
        XCTAssertNil(store.departuresError)
    }

    @MainActor func testFailedFirstStopsRequestHasErrorAndNoFalseEmptyBoard() async {
        var api = client(); api.stops = { _, _ in throw APIError.requestFailed }
        api.batch = { _ in XCTFail("No departures without stops"); throw APIError.requestFailed }
        let store = makeStore(api)
        await store.loadArea(area)
        XCTAssertNotNil(store.stopsError)
        XCTAssertNil(store.stopsCheckedAt)
        XCTAssertNil(store.home.checkedAt)
        XCTAssertFalse(store.isLoadingStops)
    }

    @MainActor func testEmptyStopsAndEmptyDeparturesAreDifferentStates() async throws {
        var api = client(); api.stops = { _, _ in [] }
        let noStops = makeStore(api)
        await noStops.loadArea(area)
        XCTAssertNotNil(noStops.stopsCheckedAt); XCTAssertTrue(noStops.stops.isEmpty)
        api = try sampleClient(); let empty = try sampleBatch(empty: true); api.batch = { _ in empty }
        let noDepartures = makeStore(api)
        await noDepartures.loadArea(area)
        XCTAssertEqual(noDepartures.stops.count, 17)
        XCTAssertNotNil(noDepartures.home.checkedAt); XCTAssertTrue(noDepartures.displayedOptions.isEmpty)
        XCTAssertFalse(noDepartures.needsListRefresh(at: instant))
    }

    @MainActor func testPinWithNoSoonDepartureStaysDimAndPresentInMap() async throws {
        let disk = persistence(), stops = try sampleStops(), response = try sampleBatch()
        let night = response.boards[0].groups[1].line
        let pin = StopLineSelection(stop: stops[0], line: night, lineIndex: 1)
        disk.savePins([pin])
        let store = makeStore(try sampleClient(), persistence: disk)
        await store.loadArea(area)
        XCTAssertEqual(store.nearbyPins.map(\.id), [pin.id])
        let content = HomeRowContent(board: store.home.boards[pin.id], fresh: true, pinned: true, now: instant)
        XCTAssertTrue(content.idle); XCTAssertEqual(content.answer, "Nothing soon")
        XCTAssertTrue(store.mapGroups[0].lines.contains(night))
    }

    @MainActor func testMapUsesOnlyListedLinesAndOneAnnotationPerPhysicalStop() async throws {
        let store = makeStore(try sampleClient())
        await store.loadArea(area)
        XCTAssertEqual(store.mapGroups.count, 4)
        XCTAssertEqual(store.mapGroups[0].lines.map(\.name), ["13A", "49"])
        XCTAssertEqual(store.mapGroups[1].active.count, 1)
        let marker = StopsMapView.StopAnnotation(group: store.mapGroups[0])
        XCTAssertEqual(marker.lines.map(\.name), ["13A", "49"])
        XCTAssertEqual(marker.spokenLabel, "Siebensterngasse, Bus 13A and Tram 49")
    }

    @MainActor func testHomePublishesBeforeSlowWalkingAndWalkingNeverReorders() async throws {
        let started = expectation(description: "routes started"); started.expectedFulfillmentCount = 3
        var finishes: [CheckedContinuation<WalkingRoute, Error>] = []
        var api = try sampleClient()
        let route = route()
        api.directions = { _, _ in
            if finishes.count >= 3 { return route }
            return try await withCheckedThrowingContinuation { finishes.append($0); started.fulfill() }
        }
        let store = makeStore(api)
        await store.loadArea(area)
        await fulfillment(of: [started], timeout: 2)
        let before = store.displayedOptions.map(\.id)
        XCTAssertEqual(before.count, 8)
        for finish in finishes { finish.resume(returning: route) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.displayedOptions.map(\.id), before)
    }

    func testCountdownUsesNowBelowAMinuteAndClockBeyondTheHour() {
        XCTAssertEqual(TimeFormatter.countdown(departure(0.99).time, now: instant), "Now")
        XCTAssertEqual(TimeFormatter.countdown(departure(1).time, now: instant), "In 1 min")
        XCTAssertEqual(TimeFormatter.countdown(departure(60).time, now: instant), "In 60 min")
        XCTAssertNil(TimeFormatter.countdown(departure(60.1).time, now: instant))
    }

    func testBatchURLPreservesHostAndEncodesIdentifiers() throws {
        let url = try APIService.batchDeparturesURL(stopIDs: ["one: a", "two/b"])
        XCTAssertEqual(url.host, "departs.vercel.app")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, [.init(name: "stopIds", value: "one: a,two/b")])
        XCTAssertThrowsError(try APIService.batchDeparturesURL(stopIDs: []))
        XCTAssertThrowsError(try APIService.batchDeparturesURL(stopIDs: (0..<51).map(String.init)))
    }

    func testLineShowsCountdownAndClockThroughSixtyMinutesThenOnlyClock() {
        let soon = LineDepartureContent(departure: departure(60, live: false), fresh: true, now: instant)
        XCTAssertEqual(soon.countdown, "In 60 min")
        XCTAssertEqual(soon.clock, TimeFormatter.formatTime(departure(60).time))
        let later = LineDepartureContent(departure: departure(61, live: false), fresh: true, now: instant)
        XCTAssertNil(later.countdown)
        XCTAssertEqual(later.spoken, later.clock)
        XCTAssertFalse(later.live)
    }

    func testLineDelayRequiresLiveDataAndAFullMinute() {
        func content(_ seconds: Double, live: Bool = true, fresh: Bool = true) -> LineDepartureContent {
            .init(departure: .init(time: departure(3).time, realTime: live, delay: seconds, line: line), fresh: fresh, now: instant)
        }
        XCTAssertNil(content(59).delay)
        XCTAssertEqual(content(60).delay, "1 min late")
        XCTAssertEqual(content(119).delay, "1 min late")
        XCTAssertNil(content(180, live: false).delay)
        let saved = content(180, fresh: false)
        XCTAssertFalse(saved.live)
        XCTAssertNil(saved.delay)
        XCTAssertNil(saved.countdown)
        XCTAssertEqual(saved.spoken, saved.clock)
    }

    @MainActor func testLineOpensWithTwoThenFetchesFourAndItsOwnPlatformRoute() async throws {
        var api = try sampleClient(), detailCalls = 0
        var destinations: [Coordinate] = []
        let four = [departure(2), departure(6), departure(10), departure(14)], route = route()
        api.departures = { _ in detailCalls += 1; return four }
        api.directions = { _, to in destinations.append(to); return route }
        let store = makeStore(api)
        await store.updateLocation(fix)
        for _ in 0..<20 { await Task.yield() }
        let selection = try XCTUnwrap(store.displayedOptions.first { $0.line.name == "48A" })
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 2)
        XCTAssertFalse(destinations.contains(selection.stop.location), "Home walks to the merged stop's nearest platform")
        await store.refreshSelection(selection)
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 4)
        XCTAssertEqual(detailCalls, 1)
        XCTAssertTrue(destinations.contains(selection.stop.location), "Line screen must walk to its own platform")
        let destination = WalkingDirections.destination(for: selection)
        XCTAssertEqual(destination.location.coordinate.latitude, selection.stop.location.lat)
        XCTAssertEqual(destination.location.coordinate.longitude, selection.stop.location.lon)
        XCTAssertEqual(destination.name, selection.stop.name)
        await store.refreshAnswers(force: true)
        await store.refreshSelection(selection)
        XCTAssertEqual(detailCalls, 1, "Reopening a recent line reuses its complete board")
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 4, "A home batch must not replace four times with two")
    }

    @MainActor func testLineFailureKeepsFourClockTimesAndOneRefreshRestoresCountdowns() async {
        var api = client(), fail = false, calls = 0
        let values = [departure(2), departure(6), departure(10), departure(14)]
        api.departures = { _ in calls += 1; if fail { throw APIError.requestFailed }; return values }
        let store = makeStore(api), selection = stop().lineSelections[0]
        await store.refreshBoard(selection)
        fail = true
        await store.refreshBoard(selection, force: true)
        XCTAssertFalse(store.isBoardFresh(for: selection, at: instant))
        XCTAssertEqual(store.boards[selection.id]?.departures.map(\.time), values.map(\.time))
        XCTAssertTrue(values.allSatisfy { LineDepartureContent(departure: $0, fresh: false, now: instant).countdown == nil })
        fail = false
        await store.refreshBoard(selection, force: true)
        XCTAssertEqual(calls, 3)
        XCTAssertTrue(store.isBoardFresh(for: selection, at: instant))
    }

    @MainActor func testShortcutPerformsWithTheStablePinnedDirection() async throws {
        let selection = stop().lineSelections[0]
        let intent = OpenPinnedRouteIntent()
        intent.route = PinnedRouteEntity(selection)
        _ = try await intent.perform()
        XCTAssertEqual(RouteNavigation.shared.pinnedRouteID, selection.id)
        RouteNavigation.shared.pinnedRouteID = nil
    }

    @MainActor func testLineOpenedAfterFailedHomeRefreshKeepsSavedTimesUntilRevalidated() async throws {
        var api = try sampleClient(), fail = false
        let batch = try sampleBatch(), values = [departure(2), departure(6), departure(10), departure(14)]
        api.batch = { _ in if fail { throw APIError.requestFailed }; return batch }
        api.departures = { _ in values }
        let store = makeStore(api)
        await store.loadArea(area)
        let selection = store.displayedOptions[0]
        fail = true
        await store.refreshAnswers(force: true)
        XCTAssertFalse(store.isBoardFresh(for: selection, at: instant))
        await store.refreshBoard(selection)
        XCTAssertTrue(store.isBoardFresh(for: selection, at: instant))
        XCTAssertFalse(store.isHomeBoardFresh(for: selection, at: instant), "Detail recovery does not silently certify the whole home batch")
    }

    @MainActor func testHomeRecoveryCannotCertifyAFailedFirstLineRequest() async throws {
        var api = try sampleClient()
        api.departures = { _ in throw APIError.requestFailed }
        let store = makeStore(api)
        await store.loadArea(area)
        let selection = store.displayedOptions[0]
        await store.refreshBoard(selection)
        XCTAssertTrue(store.boardErrors.contains(selection.id))
        await store.refreshAnswers(force: true)
        XCTAssertTrue(store.isHomeBoardFresh(for: selection, at: instant))
        XCTAssertFalse(store.isBoardFresh(for: selection, at: instant))
        XCTAssertTrue(store.boardErrors.contains(selection.id))
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
        XCTAssertTrue(advice.detail.contains("scheduled departure"))
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
