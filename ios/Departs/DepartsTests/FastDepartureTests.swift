import XCTest
import Observation
import MapKit
import SwiftUI
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
    private func persistence(suite: String = "departs.tests.\(UUID())") -> TransitPersistence {
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return .init(defaults: defaults)
    }
    private func client() -> TransitClient {
        let stops = [stop()]; let departures = [departure(7), departure(12)]; let walk = route()
        let fetchedAt = instant.ISO8601Format()
        return .init(stops: { _ in stops }, departures: { _ in departures }, directions: { _, _ in walk },
                     batch: { ids in .init(fetchedAt: fetchedAt, boards: ids.map {
                         .init(stopId: $0, groups: [.init(line: stops[0].lines[0], departures: departures)])
                     }, missing: []) })
    }
    @MainActor private func makeStore(_ client: TransitClient? = nil, persistence storage: TransitPersistence? = nil) -> TransitStore {
        let date = instant
        return TransitStore(client: client ?? self.client(), persistence: storage ?? persistence(), now: { date })
    }
    private var fix: LocationFix { .init(coordinate: coordinate, capturedAt: instant, accuracy: 10) }

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
        api.stops = { _ in stops }
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
            BatchDepartures.Group(line: service("\(index)", "End"), departures: [departure(minutes)])
        }
        var api = client()
        api.stops = { _ in [inside, outside] }
        let response = BatchDepartures(fetchedAt: instant.ISO8601Format(), boards: [.init(stopId: inside.id, groups: groups)], missing: [])
        api.batch = { ids in XCTAssertEqual(ids, [inside.id]); return response }
        let store = makeStore(api)
        await store.loadArea(coordinate)
        XCTAssertEqual(store.displayedOptions.map(\.line.name), ["1", "2"])
        XCTAssertEqual(store.stops.map(\.id), [inside.id])
    }

    @MainActor func testOpeningUsesOneBatchAndFourWalksThenOneBatchPerRefresh() async throws {
        var api = try sampleClient(), stopCalls = 0, batchCalls = 0, walkCalls = 0, detailCalls = 0
        let stops = try sampleStops(), response = try sampleBatch(), route = route()
        let walks = expectation(description: "one route per listed physical stop"); walks.expectedFulfillmentCount = 4
        api.stops = { _ in stopCalls += 1; return stops }
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

    @MainActor func testDetailUsesInjectedWalkingRoute() async {
        let platform = stop()
        let selection = StopLineSelection(stop: platform, line: line, lineIndex: 0)
        let expectedRoute = route()
        var api = client()
        var requests = 0
        api.directions = { origin, destination in
            requests += 1
            XCTAssertEqual(origin, self.coordinate)
            XCTAssertEqual(destination, platform.location)
            return expectedRoute
        }

        let store = makeStore(api)
        store.setWalkingDemand(showsList: false, selectedStops: [selection.stop])
        await store.updateLocation(fix, showing: selection)
        await store.refreshSelection(selection, force: true)
        await Task.yield()

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(store.walk(for: platform, at: instant)?.route, expectedRoute)
        XCTAssertEqual(store.boards[selection.id]?.departures.map(\.time), [departure(7).time, departure(12).time])
    }

    @MainActor func testWalkingErrorsLeaveDeparturesFresh() async {
        let platform = stop()
        let selection = StopLineSelection(stop: platform, line: line, lineIndex: 0)
        let errors: [Error] = [MKError(.loadingThrottled), MKError(.directionsNotFound), CancellationError()]
        for error in errors {
            var api = client()
            var requests = 0
            api.directions = { _, _ in requests += 1; throw error }
            let store = makeStore(api)
            store.setWalkingDemand(showsList: false, selectedStops: [selection.stop])

            await store.updateLocation(fix, showing: selection)
            await Task.yield()
            await store.refreshSelection(selection, force: true)
            await Task.yield()

            XCTAssertEqual(requests, 2, "A failed walk can be requested again")
            XCTAssertNil(store.walk(for: platform, at: instant))
            XCTAssertEqual(store.boards[selection.id]?.departures.map(\.time), [departure(7).time, departure(12).time])
            XCTAssertTrue(store.isBoardFresh(for: selection, at: instant))
            XCTAssertNil(store.departuresError)
        }
    }

    @MainActor func testFailedBatchKeepsEveryRowAndTimeButUsesClockWithoutFanout() async throws {
        var api = try sampleClient(), failed = false, individualCalls = 0
        let response = try sampleBatch()
        api.batch = { _ in if failed { throw APIError.requestFailed }; return response }
        api.departures = { _ in individualCalls += 1; return [] }
        let store = makeStore(api)
        await store.loadArea(coordinate)
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
        await store.loadArea(coordinate)
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
        await store.loadArea(coordinate)
        XCTAssertEqual(store.groups.filter(\.hasMissingBoard).count, 1)
        XCTAssertEqual(store.groups.first?.name, "Siebensterngasse")
        XCTAssertTrue(store.groups.first!.active.isEmpty)
    }

    @MainActor func testProviderTimestampIncludesCDNAgeInFreshness() async throws {
        let response = try sampleBatch(at: instant.addingTimeInterval(-30))
        var api = try sampleClient(); api.batch = { _ in response }
        let store = makeStore(api)
        await store.loadArea(coordinate)
        let selection = store.displayedOptions[0]
        XCTAssertTrue(store.isHomeBoardFresh(for: selection, at: instant))
        XCTAssertFalse(store.isHomeBoardFresh(for: selection, at: instant.addingTimeInterval(31)))
        XCTAssertEqual(store.home.boards[selection.id]?.checkedAt, instant.addingTimeInterval(-30))
    }

    @MainActor func testRelaunchShowsExactSavedListImmediatelyUntilRevalidation() async throws {
        let disk = persistence(), api = try sampleClient()
        let first = makeStore(api, persistence: disk)
        await first.loadArea(coordinate)
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
        await store.loadArea(coordinate)
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
        let first = Task { await store.loadArea(coordinate) }
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
        var api = client(); api.stops = { _ in throw APIError.requestFailed }
        api.batch = { _ in XCTFail("No departures without stops"); throw APIError.requestFailed }
        let store = makeStore(api)
        await store.loadArea(coordinate)
        XCTAssertNotNil(store.stopsError)
        XCTAssertNil(store.stopsCheckedAt)
        XCTAssertNil(store.home.checkedAt)
        XCTAssertFalse(store.isLoadingStops)
    }

    @MainActor func testEmptyStopsAndEmptyDeparturesAreDifferentStates() async throws {
        var api = client(); api.stops = { _ in [] }
        let noStops = makeStore(api)
        await noStops.loadArea(coordinate)
        XCTAssertNotNil(noStops.stopsCheckedAt); XCTAssertTrue(noStops.stops.isEmpty)
        api = try sampleClient(); let empty = try sampleBatch(empty: true); api.batch = { _ in empty }
        let noDepartures = makeStore(api)
        await noDepartures.loadArea(coordinate)
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
        await store.loadArea(coordinate)
        XCTAssertEqual(store.nearbyPins.map(\.id), [pin.id])
        let content = HomeRowContent(board: store.home.boards[pin.id], fresh: true, pinned: true, now: instant)
        XCTAssertTrue(content.idle); XCTAssertEqual(content.answer, "Nothing soon")
        XCTAssertTrue(store.mapGroups[0].lines.contains(night))
    }

    @MainActor func testMapUsesOnlyListedLinesAndOneAnnotationPerPhysicalStop() async throws {
        let store = makeStore(try sampleClient())
        await store.loadArea(coordinate)
        XCTAssertEqual(store.mapGroups.count, 4)
        XCTAssertEqual(store.mapGroups[0].lines.map(\.name), ["13A", "49"])
        XCTAssertEqual(store.mapGroups[1].active.count, 1)
        let marker = StopsMapView.StopAnnotation(group: store.mapGroups[0])
        XCTAssertEqual(marker.lines.map(\.name), ["13A", "49"])
        XCTAssertEqual(marker.spokenLabel, "Siebensterngasse, Bus 13A and Tram 49")
    }

    @MainActor func testHomePublishesBeforeSlowWalkingAndWalkingNeverReorders() async throws {
        let started = expectation(description: "routes started")
        started.expectedFulfillmentCount = 3
        let probe = WalkingProbe()
        probe.onStart = { _ in started.fulfill() }
        let service = WalkingRouteService(start: probe.start)
        var api = try sampleClient()
        api.directions = { try await service.route(from: $0, to: $1) }
        let store = makeStore(api)
        await store.loadArea(coordinate)
        await fulfillment(of: [started], timeout: 2)
        let before = store.displayedOptions.map(\.id)
        XCTAssertEqual(before.count, 8)
        let fourth = expectation(description: "fourth route")
        probe.onStart = { _ in fourth.fulfill() }
        probe.complete(0)
        await fulfillment(of: [fourth], timeout: 2)
        for index in 1...3 { probe.complete(index) }
        XCTAssertEqual(store.displayedOptions.map(\.id), before)
    }

    @MainActor func testDepartureClockTicksWhileWalkingIsStalled() async {
        let timestamp = Date.now
        var date = timestamp
        var api = client()
        api.stops = { _ in [] }
        let initialBoard = expectation(description: "initial board")
        let nextBoard = expectation(description: "next board while walk is stalled")
        var boardCount = 0
        api.departures = { _ in
            boardCount += 1
            if boardCount == 1 { initialBoard.fulfill() }
            if boardCount == 2 { nextBoard.fulfill() }
            return [self.departure(7)]
        }

        let probe = WalkingProbe()
        let started = expectation(description: "walk started")
        probe.onStart = { _ in started.fulfill() }
        let service = WalkingRouteService(start: probe.start)
        api.directions = { try await service.route(from: $0, to: $1) }
        let store = TransitStore(client: api, persistence: persistence(), now: { date })
        let selection = StopLineSelection(stop: stop(), line: line, lineIndex: 0)
        await store.updateLocation(.init(coordinate: coordinate, capturedAt: timestamp, accuracy: 10))

        let sleeping = expectation(description: "foreground clock reached its wait")
        let clock = AsyncGate()
        let session = TransitSession(store: store, authorizationStatus: { .authorizedWhenInUse }, waitForRefresh: {
            if boardCount == 1 { sleeping.fulfill() }
            try await clock.wait()
        })
        let window = UUID()
        session.updateWindow(window, active: true, showsList: false, selection: selection)
        await fulfillment(of: [initialBoard, started, sleeping], timeout: 2)
        date += 61
        clock.resume()
        await fulfillment(of: [nextBoard], timeout: 2)
        XCTAssertTrue(store.isBoardFresh(for: selection, at: date))
        XCTAssertEqual(probe.active, 1)
        session.updateWindow(window, active: false, showsList: false, selection: nil)
        clock.resume()
        store.clearArea()
    }

    @MainActor func testOriginABARejectsLateRoutesInStoreAndServiceCache() async throws {
        let probe = WalkingProbe()
        let service = WalkingRouteService(start: probe.start)
        var api = client()
        api.directions = { try await service.route(from: $0, to: $1) }
        let store = makeStore(api)
        let platform = stop()
        let selection = StopLineSelection(stop: platform, line: line, lineIndex: 0)
        store.setWalkingDemand(showsList: false, selectedStops: [platform])
        let b = Coordinate(lat: coordinate.lat + 0.00051, lon: coordinate.lon)
        for origin in [coordinate, b, coordinate] {
            let started = expectation(description: "request at \(origin)")
            probe.onStart = { _ in started.fulfill() }
            await store.updateLocation(.init(coordinate: origin, capturedAt: instant, accuracy: 10), showing: selection)
            await fulfillment(of: [started], timeout: 2)
        }

        XCTAssertEqual(probe.cancelled, [0, 1])
        probe.complete(2, duration: 200)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.walk(for: platform, at: instant)?.route.duration, 200)
        probe.complete(1, duration: 100)
        probe.complete(0, duration: 300)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.walk(for: platform, at: instant)?.route.duration, 200)
        let cached = try await service.route(from: coordinate, to: platform.location)
        XCTAssertEqual(cached.duration, 200)
        XCTAssertEqual(probe.started, 3)
    }

    @MainActor func testMovingDuringHomeRefreshKeepsGlobalWalkingLimit() async throws {
        let probe = WalkingProbe()
        let service = WalkingRouteService(start: probe.start)
        var api = try sampleClient()
        api.directions = { try await service.route(from: $0, to: $1) }
        let store = makeStore(api)

        let first = expectation(description: "three original routes")
        first.expectedFulfillmentCount = 3
        probe.onStart = { _ in first.fulfill() }
        await store.updateLocation(fix)
        await fulfillment(of: [first], timeout: 2)

        let moved = expectation(description: "three routes for the new origin")
        moved.expectedFulfillmentCount = 3
        probe.onStart = { _ in moved.fulfill() }
        let coordinate = Coordinate(lat: self.coordinate.lat + 0.00051, lon: self.coordinate.lon)
        await store.updateLocation(.init(coordinate: coordinate, capturedAt: instant, accuracy: 10), force: true)
        await fulfillment(of: [moved], timeout: 2)
        XCTAssertEqual(Set(probe.cancelled), [0, 1, 2])
        XCTAssertEqual(probe.peak, 3)
        XCTAssertEqual(probe.active, 3)
        store.clearArea()
    }

    private func walkingDemandStops(_ count: Int) -> [NearbyStop] {
        (0..<count).map { index in
            let line = LineInfo(name: String(index), direction: "Centre", type: .bus)
            let point = Coordinate(lat: coordinate.lat + Double(index) * 0.00018, lon: coordinate.lon)
            return .init(id: "stop-\(index)", name: "Stop \(index)", type: .bus, lines: [line], location: point, distance: nil)
        }
    }

    private func walkingDemandBatch(_ stops: [NearbyStop], showing visible: Set<String>, at date: Date) -> BatchDepartures {
        let boards = stops.map { stop in
            let groups: [BatchDepartures.Group] = visible.contains(stop.id) ? stop.lines.map { line in
                let time = date.addingTimeInterval(420).ISO8601Format()
                return BatchDepartures.Group(line: line, departures: [.init(time: time, realTime: false, delay: nil, line: line)])
            } : []
            return BatchDepartures.Board(stopId: stop.id, groups: groups)
        }
        return .init(fetchedAt: date.ISO8601Format(), boards: boards, missing: [])
    }

    @MainActor func testWalkDemandCancelsRemovedStopsKeepsWantedWalksAndPromotesSelection() async throws {
        let date = Date.now
        let stops = walkingDemandStops(10)
        let replacement = try XCTUnwrap(stops.last)
        let original = Set(stops.dropLast().map(\.id))
        var visible = original
        let probe = WalkingProbe()
        let service = WalkingRouteService(now: { date }, sleep: { _ in try await Task.sleep(for: .seconds(300)) }, start: probe.start)
        let admitted = expectation(description: "all nine original walks requested")
        admitted.expectedFulfillmentCount = 9
        let cancelled = expectation(description: "all nine original walkers cancelled")
        cancelled.expectedFulfillmentCount = 9
        var submissions: [Coordinate] = []
        let originals = Set(stops.dropLast().map(\.location))

        var api = client()
        api.stops = { _ in stops }
        api.batch = { _ in self.walkingDemandBatch(stops, showing: visible, at: date) }
        api.prioritizeWalks = { service.prioritize(destinations: $0) }
        api.directions = { origin, destination in
            let firstRound = visible == original && originals.contains(destination)
            submissions.append(destination)
            if firstRound { admitted.fulfill() }
            defer { if firstRound && Task.isCancelled { cancelled.fulfill() } }
            return try await service.route(from: origin, to: destination)
        }
        let store = TransitStore(client: api, persistence: persistence(), now: { date })
        let session = TransitSession(store: store, authorizationStatus: { .authorizedWhenInUse })
        let home = UUID()
        let detail = UUID()
        await store.updateLocation(.init(coordinate: coordinate, capturedAt: date, accuracy: 10))
        session.updateWindow(home, active: true, showsList: true, selection: nil)
        defer {
            session.updateWindow(detail, active: false, showsList: false, selection: nil)
            session.updateWindow(home, active: false, showsList: false, selection: nil)
        }
        await fulfillment(of: [admitted], timeout: 2)
        XCTAssertEqual(probe.started, 3)

        visible = [replacement.id]
        let startedReplacement = expectation(description: "replacement starts before obsolete callbacks")
        probe.onStart = { _ in startedReplacement.fulfill() }
        await store.refreshAnswers(force: true)
        let selection = StopLineSelection(stop: replacement, line: replacement.lines[0], lineIndex: 0)
        session.updateWindow(home, active: true, showsList: false, selection: selection)
        await fulfillment(of: [cancelled, startedReplacement], timeout: 2)
        XCTAssertEqual(probe.destinations.dropFirst(3), [replacement.location])
        XCTAssertEqual(Set(probe.cancelled), [0, 1, 2])
        for index in 0..<3 { probe.complete(index) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(store.walks.isEmpty, "Late obsolete results never reach the store")

        // Keep the replacement wanted across a home snapshot change, then
        // select a queued platform while Home still wants the other walks.
        probe.onStart = nil
        session.updateWindow(home, active: true, showsList: true, selection: nil)
        visible = Set(stops.map(\.id))
        await store.refreshAnswers(force: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(submissions.count, 19)
        XCTAssertEqual(probe.active, 3)
        XCTAssertFalse(probe.cancelled.contains(3), "The replacement is still wanted")
        let activeDestinations = Set(probe.destinations.dropFirst(3))
        let queued = submissions.dropFirst(10).filter { !activeDestinations.contains($0) }
        XCTAssertGreaterThan(queued.count, 1)
        let destination = try XCTUnwrap(queued.last)
        let chosen = try XCTUnwrap(stops.first { $0.location == destination })
        let chosenLine = StopLineSelection(stop: chosen, line: chosen.lines[0], lineIndex: 0)
        session.updateWindow(detail, active: true, showsList: false, selection: chosenLine)
        let promoted = expectation(description: "selected platform goes before queued home routes")
        probe.onStart = { _ in promoted.fulfill() }
        probe.complete(4)
        await fulfillment(of: [promoted], timeout: 2)
        XCTAssertEqual(probe.destinations.last, chosen.location)
        XCTAssertEqual(probe.peak, 3)
    }

    @MainActor func testWalkingDemandStopsInBackgroundAndResumesInForeground() async {
        let date = Date.now
        let stops = walkingDemandStops(4)
        let probe = WalkingProbe()
        let service = WalkingRouteService(now: { date }, sleep: { _ in try await Task.sleep(for: .seconds(300)) }, start: probe.start)
        let requests = expectation(description: "four routes admitted, one queued")
        requests.expectedFulfillmentCount = 4
        var submitted = 0
        var api = client()
        api.stops = { _ in stops }
        api.batch = { _ in self.walkingDemandBatch(stops, showing: Set(stops.map(\.id)), at: date) }
        api.prioritizeWalks = { service.prioritize(destinations: $0) }
        api.directions = { origin, destination in
            submitted += 1
            if submitted <= 4 { requests.fulfill() }
            return try await service.route(from: origin, to: destination)
        }
        let store = TransitStore(client: api, persistence: persistence(), now: { date })
        let session = TransitSession(store: store, authorizationStatus: { .authorizedWhenInUse })
        let window = UUID()
        await store.updateLocation(.init(coordinate: coordinate, capturedAt: date, accuracy: 10))
        XCTAssertEqual(submitted, 0, "A snapshot can arrive before the first active window")
        session.updateWindow(window, active: true, showsList: true, selection: nil)
        await fulfillment(of: [requests], timeout: 2)
        XCTAssertEqual(probe.started, 3)

        session.updateWindow(window, active: false, showsList: false, selection: nil)
        probe.complete(0)
        await store.refreshAnswers(force: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(submitted, 4)
        XCTAssertEqual(probe.started, 3)
        XCTAssertEqual(Set(probe.cancelled), [0, 1, 2])
        XCTAssertTrue(store.walks.isEmpty)

        let resumed = expectation(description: "foreground restores walking demand")
        resumed.expectedFulfillmentCount = 3
        probe.onStart = { _ in resumed.fulfill() }
        session.updateWindow(window, active: true, showsList: true, selection: nil)
        await fulfillment(of: [resumed], timeout: 2)
        XCTAssertEqual(probe.active, 3)
        session.updateWindow(window, active: false, showsList: false, selection: nil)
    }

    @MainActor private func savedWalkingArea(authorizationStatus: @escaping () -> CLAuthorizationStatus)
        -> (session: TransitSession, probe: WalkingProbe, disk: TransitPersistence, selection: StopLineSelection) {
        let date = Date.now
        let stops = walkingDemandStops(4)
        let disk = persistence()
        let visible = Set(stops.map(\.id))
        let batch = walkingDemandBatch(stops, showing: visible, at: date)
        disk.saveNearby(.init(center: coordinate, stops: stops, checkedAt: date))
        disk.saveHome(.make(stops: stops, origin: coordinate, pins: [], response: batch, checkedAt: date))
        let probe = WalkingProbe()
        let walking = WalkingRouteService(now: { date }, start: probe.start)
        var api = client()
        api.stops = { _ in stops }
        api.batch = { _ in batch }
        api.directions = { try await walking.route(from: $0, to: $1) }
        let store = TransitStore(client: api, persistence: disk, now: { date })
        let session = TransitSession(store: store, authorizationStatus: authorizationStatus)
        let selection = StopLineSelection(stop: stops[0], line: stops[0].lines[0], lineIndex: 0)
        return (session, probe, disk, selection)
    }

    @MainActor func testColdLaunchNeverStartsWalksWithDeniedOrRestrictedAuthorization() async {
        for status: CLAuthorizationStatus in [.denied, .restricted] {
            for showsList in [true, false] {
                let (session, probe, disk, selection) = savedWalkingArea { status }
                XCTAssertTrue(session.store.homeRestored)
                let window = UUID()
                session.updateWindow(window, active: true, showsList: showsList, selection: showsList ? nil : selection)
                XCTAssertNil(disk.loadNearby(), "Foreground entry must clear the saved area synchronously")
                await session.refreshVisibleAnswers()
                for _ in 0..<20 { await Task.yield() }
                XCTAssertEqual(probe.started, 0, "Authorization \(status.rawValue), showsList \(showsList)")
                session.updateWindow(window, active: false, showsList: false, selection: nil)
            }
        }
    }

    @MainActor func testForegroundDoesNotRestartWalksAfterAuthorizationWasRevokedInBackground() async {
        for revoked: CLAuthorizationStatus in [.denied, .restricted] {
            var status = CLAuthorizationStatus.authorizedWhenInUse
            let (session, probe, disk, _) = savedWalkingArea { status }
            let window = UUID()
            let granted = expectation(description: "three active walks before revocation")
            granted.expectedFulfillmentCount = 3
            probe.onStart = { _ in granted.fulfill() }
            session.updateWindow(window, active: true, showsList: true, selection: nil)
            await fulfillment(of: [granted], timeout: 2)
            session.updateWindow(window, active: false, showsList: false, selection: nil)
            probe.onStart = nil
            status = revoked

            session.updateWindow(window, active: true, showsList: true, selection: nil)
            XCTAssertNil(disk.loadNearby())
            await session.refreshVisibleAnswers()
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(probe.started, 3)
            XCTAssertEqual(probe.active, 0)
            session.updateWindow(window, active: false, showsList: false, selection: nil)
        }
    }

    @MainActor func testColdLaunchStartsWantedWalksWithGrantedAuthorization() async {
        for status: CLAuthorizationStatus in [.authorizedWhenInUse, .authorizedAlways] {
            for showsList in [true, false] {
                let (session, probe, _, selection) = savedWalkingArea { status }
                let window = UUID()
                let started = expectation(description: "visible routes with a grant")
                let expectedCount = showsList ? 3 : 1
                started.expectedFulfillmentCount = expectedCount
                probe.onStart = { _ in started.fulfill() }
                session.updateWindow(window, active: true, showsList: showsList, selection: showsList ? nil : selection)
                await fulfillment(of: [started], timeout: 2)
                XCTAssertEqual(probe.started, expectedCount)
                session.updateWindow(window, active: false, showsList: false, selection: nil)
            }
        }
    }

    @MainActor func testUndeterminedAuthorizationPreservesRefreshTriggeredWalks() async {
        for showsList in [true, false] {
            let (session, probe, _, selection) = savedWalkingArea { .notDetermined }
            let window = UUID()
            let started = expectation(description: "refresh starts the visible walks")
            started.expectedFulfillmentCount = showsList ? 3 : 1
            probe.onStart = { _ in started.fulfill() }
            session.updateWindow(window, active: true, showsList: showsList, selection: showsList ? nil : selection)
            XCTAssertEqual(probe.started, 0, "Activation alone must not start MapKit before the prompt")
            await session.refreshVisibleAnswers()
            await fulfillment(of: [started], timeout: 2)
            session.updateWindow(window, active: false, showsList: false, selection: nil)
        }
    }

    @MainActor private func authorizationRace(
        authorization: @escaping () -> CLAuthorizationStatus,
        now: @escaping () -> Date,
        onBatch: @escaping () -> Void = {},
        onRoute: @escaping () -> Void = {},
        waitForRefresh: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(30)) }
    ) -> (session: TransitSession, service: WalkingRouteService, probe: WalkingProbe) {
        let stops = walkingDemandStops(9)
        let disk = persistence()
        let probe = WalkingProbe()
        let service = WalkingRouteService(now: now, isAuthorized: {
            WalkingRouteService.permitsWalking(authorization())
        }, start: probe.start)
        var api = client()
        api.stops = { _ in stops }
        api.batch = { _ in
            onBatch()
            return self.walkingDemandBatch(stops, showing: Set(stops.map(\.id)), at: now())
        }
        api.directions = { origin, destination in
            let route = try await service.route(from: origin, to: destination)
            onRoute()
            return route
        }
        api.checkWalkingAuthorization = { service.checkAuthorization() }
        let date = now()
        let batch = walkingDemandBatch(stops, showing: Set(stops.map(\.id)), at: date)
        disk.saveNearby(.init(center: coordinate, stops: stops, checkedAt: date))
        disk.saveHome(.make(stops: stops, origin: coordinate, pins: [], response: batch, checkedAt: date))
        let store = TransitStore(client: api, persistence: disk, now: now)
        return (TransitSession(store: store, authorizationStatus: authorization, waitForRefresh: waitForRefresh), service, probe)
    }

    @MainActor private func assertWalkingRequests(_ count: Int, session: TransitSession,
                                                   service: WalkingRouteService,
                                                   file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if session.store.pendingWalkCount == count && service.pendingRequestCount == count { break }
            await Task.yield()
        }
        XCTAssertEqual(session.store.pendingWalkCount, service.pendingRequestCount, file: file, line: line)
        XCTAssertEqual(service.pendingRequestCount, count, file: file, line: line)
    }

    @MainActor func testRevokedCompletionCannotPublishOrPopulateCacheInEitherCallbackOrder() async {
        for notifyFirst in [false, true] {
            var status = CLAuthorizationStatus.authorizedWhenInUse
            let date = Date.now
            let (session, service, probe) = authorizationRace(authorization: { status }, now: { date })
            let window = UUID()
            defer { session.updateWindow(window, active: false, showsList: false, selection: nil) }
            session.updateWindow(window, active: true, showsList: true, selection: nil)
            await assertWalkingRequests(9, session: session, service: service)
            XCTAssertEqual(probe.started, 3)

            status = .denied
            if notifyFirst { session.receivedLocation() }
            for index in 0..<3 { probe.complete(index) }
            await assertWalkingRequests(0, session: session, service: service)
            XCTAssertTrue(session.store.walks.isEmpty)
            XCTAssertEqual(probe.started, 3)
            XCTAssertEqual(probe.active, 0)
            if !notifyFirst { session.receivedLocation() }

            status = .authorizedWhenInUse
            session.updateWindow(window, active: true, showsList: true, selection: nil)
            await session.store.updateLocation(.init(coordinate: coordinate, capturedAt: date, accuracy: 10))
            await assertWalkingRequests(9, session: session, service: service)
            XCTAssertTrue(session.store.walks.isEmpty, "Revoked completions must miss the cache after re-grant")
            XCTAssertEqual(probe.started, 6)
        }
    }

    @MainActor func testStoreDiscardsSuccessIfAuthorizationChangesAfterServiceReturns() async {
        var status = CLAuthorizationStatus.authorizedWhenInUse
        let date = Date.now
        let (session, service, probe) = authorizationRace(authorization: { status }, now: { date }, onRoute: {
            status = .denied
        })
        let window = UUID()
        defer { session.updateWindow(window, active: false, showsList: false, selection: nil) }
        session.updateWindow(window, active: true, showsList: true, selection: nil)
        await assertWalkingRequests(9, session: session, service: service)
        probe.complete(0)
        await assertWalkingRequests(0, session: session, service: service)
        XCTAssertEqual(status, .denied)
        XCTAssertTrue(session.store.walks.isEmpty)
        XCTAssertEqual(probe.active, 0)
    }

    @MainActor func testProviderOnlyRestrictionClearsAllWalksAndNextClockRefreshRestartsThem() async {
        var status = CLAuthorizationStatus.authorizedWhenInUse
        var date = Date.now
        var batches = 0
        let clock = AsyncGate()
        let waiting = expectation(description: "foreground clock waits after the first batch")
        let nextBatch = expectation(description: "the next departure batch")
        let (session, service, probe) = authorizationRace(authorization: { status }, now: { date }, onBatch: {
            batches += 1
            if batches == 2 { nextBatch.fulfill() }
        }, waitForRefresh: {
            if batches == 1 { waiting.fulfill() }
            try await clock.wait()
        })
        let window = UUID()
        defer {
            session.updateWindow(window, active: false, showsList: false, selection: nil)
            clock.resume()
        }
        session.updateWindow(window, active: true, showsList: true, selection: nil)
        await fulfillment(of: [waiting], timeout: 2)
        await assertWalkingRequests(9, session: session, service: service)
        XCTAssertEqual(probe.started, 3)

        status = .restricted
        for index in 0..<3 { probe.complete(index) }
        await assertWalkingRequests(0, session: session, service: service)
        XCTAssertEqual(probe.started, 3)
        XCTAssertEqual(probe.active, 0)
        XCTAssertTrue(session.store.walks.isEmpty)
        XCTAssertEqual(session.store.displayedOptions.count, 9)

        // The session is still waiting on the clock. It never observes the
        // restriction, and the active window is never replaced.
        status = .authorizedWhenInUse
        date += 31
        clock.resume()
        await fulfillment(of: [nextBatch], timeout: 2)
        for offset in [0, 3, 6] {
            await assertWalkingRequests(9 - offset, session: session, service: service)
            XCTAssertEqual(probe.started, 6 + offset)
            for index in (3 + offset)..<(6 + offset) { probe.complete(index) }
        }
        await assertWalkingRequests(0, session: session, service: service)
        XCTAssertEqual(probe.active, 0)
        XCTAssertEqual(probe.peak, 3)
        XCTAssertEqual(session.store.walks.count, 9)
    }

    func testCountdownUsesNowBelowAMinuteAndClockBeyondTheHour() {
        XCTAssertEqual(TimeFormatter.countdown(departure(0.99).time, now: instant), .init(text: "Now", spoken: "Now"))
        XCTAssertEqual(TimeFormatter.countdown(departure(1).time, now: instant), .init(text: "1 min", spoken: "In 1 min"))
        XCTAssertEqual(TimeFormatter.countdown(departure(60).time, now: instant), .init(text: "60 min", spoken: "In 60 min"))
        XCTAssertNil(TimeFormatter.countdown(departure(60.1).time, now: instant))
    }

    func testHomeRowShowsMinutesWithoutInAndSpeaksTheFullPhrase() {
        func content(_ minutes: [Double], fresh: Bool = true, pinned: Bool = false) -> HomeRowContent {
            .init(board: .init(departures: minutes.map { departure($0) }, checkedAt: instant), fresh: fresh, pinned: pinned, now: instant)
        }
        let soon = content([7, 12])
        XCTAssertEqual(soon.answer, "7 min")
        XCTAssertEqual(soon.spokenAnswer, "In 7 min")
        XCTAssertEqual(content([0.5]).answer, "Now")
        XCTAssertEqual(content([0.5]).spokenAnswer, "Now")
        let saved = content([7], fresh: false)
        XCTAssertEqual(saved.answer, TimeFormatter.formatTime(departure(7).time))
        XCTAssertEqual(saved.spokenAnswer, saved.answer)
        let idle = content([90], pinned: true)
        XCTAssertEqual(idle.answer, "Nothing soon")
        XCTAssertEqual(idle.spokenAnswer, "Nothing soon")
        XCTAssertTrue(idle.idle)
    }

    func testBatchURLPreservesHostAndEncodesIdentifiers() throws {
        let url = try APIService.batchDeparturesURL(stopIDs: ["one: a", "two/b"])
        XCTAssertEqual(url.host, "api.departs.now")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, [.init(name: "stopIds", value: "one: a,two/b")])
        XCTAssertThrowsError(try APIService.batchDeparturesURL(stopIDs: []))
        XCTAssertThrowsError(try APIService.batchDeparturesURL(stopIDs: (0..<51).map(String.init)))
    }

    func testLineShowsCountdownAndClockThroughSixtyMinutesThenOnlyClock() {
        let soon = LineDepartureContent(departure: departure(60, live: false), fresh: true, now: instant)
        XCTAssertEqual(soon.countdown, "60 min")
        XCTAssertEqual(soon.clock, TimeFormatter.formatTime(departure(60).time))
        XCTAssertEqual(soon.spoken, "In 60 min. \(soon.clock)")
        let next = LineDepartureContent(departure: departure(12, live: false), fresh: true, now: instant)
        XCTAssertEqual(next.countdown, "12 min")
        XCTAssertEqual(next.spoken, "In 12 min. \(next.clock)")
        XCTAssertEqual(LineDepartureContent(departure: departure(0.4, live: false), fresh: true, now: instant).countdown, "Now")
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
        var linePlatform: Coordinate?
        let lineWalk = expectation(description: "line screen requests its own platform route")
        let four = [departure(2), departure(6), departure(10), departure(14)], route = route()
        api.departures = { _ in detailCalls += 1; return four }
        api.directions = { _, to in
            destinations.append(to)
            if to == linePlatform { lineWalk.fulfill() }
            return route
        }
        let store = makeStore(api)
        await store.updateLocation(fix)
        for _ in 0..<20 { await Task.yield() }
        let selection = try XCTUnwrap(store.displayedOptions.first { $0.line.name == "48A" })
        linePlatform = selection.stop.location
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 2)
        XCTAssertFalse(destinations.contains(selection.stop.location), "Home walks to the merged stop's nearest platform")
        store.setWalkingDemand(showsList: true, selectedStops: [selection.stop])
        await store.refreshSelection(selection)
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 4)
        XCTAssertEqual(detailCalls, 1)
        await fulfillment(of: [lineWalk], timeout: 2)
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
        await store.loadArea(coordinate)
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
        await store.loadArea(coordinate)
        let selection = store.displayedOptions[0]
        await store.refreshBoard(selection)
        XCTAssertTrue(store.boardErrors.contains(selection.id))
        await store.refreshAnswers(force: true)
        XCTAssertTrue(store.isHomeBoardFresh(for: selection, at: instant))
        XCTAssertFalse(store.isBoardFresh(for: selection, at: instant))
        XCTAssertTrue(store.boardErrors.contains(selection.id))
    }
    @MainActor func testDisplayOnlyPrefixUsesThreeDistinctSharedDirections() {
        let directions = ["PARIS NORD", "PARIS SUD", "PARIS EST"]
        XCTAssertEqual(NearbyStopsView.displayDirection("PARIS NORD", among: directions), "Nord")
        XCTAssertEqual(NearbyStopsView.displayDirection("PARIS NORD", among: Array(directions.prefix(2))), "Paris Nord")
        XCTAssertEqual(NearbyStopsView.displayDirection("PARIS NORD", among: directions + ["Lyon Centre"]), "Paris Nord")
    }

    func testShortcutDestinationUsesTitleCaseWithTheRawPinID() {
        let raw = "WIEN SKODAGASSE"
        let stop = NearbyStop(id: "312", name: "Siebensterngasse", type: .bus,
                              lines: [], location: .init(lat: 48.2, lon: 16.3), distance: nil)
        let selection = StopLineSelection(stop: stop, line: LineInfo(name: "13A", direction: raw, type: .bus), lineIndex: 0)
        let entity = PinnedRouteEntity(selection)
        XCTAssertEqual(entity.title, "13A → Wien Skodagasse")
        XCTAssertEqual(entity.id, selection.id)
        XCTAssertTrue(entity.id.contains(raw))
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
        disk.saveNearby(.init(center: coordinate, stops: [stop()], checkedAt: instant))
        disk.saveBoards([selection.id: .init(departures: [departure(7)], checkedAt: instant)])
        disk.savePins([selection])
        var calls = 0
        var api = client()
        api.stops = { _ in calls += 1; return [] }
        let store = makeStore(api, persistence: disk)
        XCTAssertEqual(store.stops.count, 1)
        XCTAssertEqual(store.boards[selection.id]?.departures.count, 1)
        XCTAssertEqual(store.pins.map(\.id), [selection.id])
        XCTAssertEqual(calls, 0)
        XCTAssertNil(store.location)
        XCTAssertFalse(store.isBoardFresh(for: selection, at: instant))
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

    @MainActor func testOlderAreaResponseCannotReplaceTheAreaTheRiderMovedTo() async {
        let started = expectation(description: "old area started")
        var finishOld: CheckedContinuation<[NearbyStop], Error>!
        let newest = stop("new")
        var api = client()
        api.stops = { coordinate in
            if coordinate.lat == 48 {
                return try await withCheckedThrowingContinuation { finishOld = $0; started.fulfill() }
            }
            return [newest]
        }
        let store = makeStore(api)
        let old = Task { await store.loadArea(.init(lat: 48, lon: 16)) }
        await fulfillment(of: [started], timeout: 2)
        await store.loadArea(coordinate)
        finishOld.resume(returning: [stop("old")])
        await old.value
        XCTAssertEqual(store.center, coordinate)
        XCTAssertEqual(store.stops.map(\.id), ["new"])
        XCTAssertFalse(store.isLoadingStops)
    }

    @MainActor func testNewFixAtTheSameSpotKeepsTheListAndRefreshesOldStopsInPlace() async throws {
        var time = instant
        var api = try sampleClient(), centers: [Coordinate] = [], rowsWhileReloading: [Int] = []
        let stops = try sampleStops()
        weak var observed: TransitStore?
        api.stops = { center in
            centers.append(center)
            rowsWhileReloading.append(observed?.displayedOptions.count ?? -1)
            return stops
        }
        let store = TransitStore(client: api, persistence: persistence(), now: { time })
        observed = store
        await store.updateLocation(fix)
        let revision = store.areaRevision
        XCTAssertEqual(store.displayedOptions.count, 8)
        // On a phone, two fixes at one spot never have identical coordinates.
        time.addTimeInterval(301)
        let fiveMetresNorth = Coordinate(lat: coordinate.lat + 5.0 / 111_200, lon: coordinate.lon)
        await store.updateLocation(.init(coordinate: fiveMetresNorth, capturedAt: time, accuracy: 10))
        XCTAssertEqual(store.areaRevision, revision, "The list must not start over when the rider has not moved")
        XCTAssertEqual(store.center, coordinate)
        XCTAssertEqual(centers, [coordinate, coordinate], "Old stops are refreshed for the same centre")
        XCTAssertEqual(rowsWhileReloading, [0, 8], "Rows stay on screen during that refresh")
        XCTAssertEqual(store.location?.coordinate, fiveMetresNorth, "Walking still starts from the newest fix")
        let twoHundredMetresNorth = Coordinate(lat: coordinate.lat + 200.0 / 111_200, lon: coordinate.lon)
        await store.updateLocation(.init(coordinate: twoHundredMetresNorth, capturedAt: time, accuracy: 10))
        XCTAssertEqual(store.areaRevision, revision + 1, "A real move is a new area")
        XCTAssertEqual(store.center, twoHundredMetresNorth)
    }

    @MainActor func testFailedStopsRefreshAtTheSameSpotKeepsTheListAndStillUpdatesTimes() async throws {
        var time = instant
        var api = try sampleClient(), failStops = false, batchCalls = 0
        let stops = try sampleStops(), response = try sampleBatch()
        api.stops = { _ in if failStops { throw APIError.requestFailed }; return stops }
        api.batch = { _ in batchCalls += 1; return response }
        let store = TransitStore(client: api, persistence: persistence(), now: { time })
        await store.updateLocation(fix)
        time.addTimeInterval(301)
        failStops = true
        await store.updateLocation(.init(coordinate: coordinate, capturedAt: time, accuracy: 10))
        XCTAssertNil(store.stopsError)
        XCTAssertFalse(store.isLoadingStops)
        XCTAssertEqual(store.displayedOptions.count, 8)
        XCTAssertEqual(batchCalls, 2)
    }

    @MainActor func testSearchedPlaceAndWiderRadiusSavedByEarlierBuildsAreNotRestored() throws {
        let disk = persistence()
        // What 1.2 (7) saved after "Search farther" at a searched place.
        let place: [String: Any] = ["coordinate": ["lat": 52.52, "lon": 13.405], "name": "Berlin", "source": "chosen"]
        let nearby: [String: Any] = ["area": place, "radius": 1600, "stops": TransitSample.stops,
                                     "checkedAt": instant.timeIntervalSinceReferenceDate]
        disk.defaults.set(try JSONSerialization.data(withJSONObject: nearby), forKey: "departs.nearby.v1")
        disk.defaults.set(try JSONSerialization.data(withJSONObject: [place]), forKey: "departs.recentAreas.v1")
        let store = makeStore(persistence: disk)
        XCTAssertNil(store.center)
        XCTAssertTrue(store.stops.isEmpty)
        XCTAssertNil(disk.defaults.data(forKey: "departs.nearby.v1"))
        XCTAssertNil(disk.defaults.data(forKey: "departs.recentAreas.v1"))
    }

    @MainActor func testLocationTurnedOffForgetsTheAreaAndKeepsPinnedRoutes() async throws {
        let disk = persistence(), response = try sampleBatch()
        var api = try sampleClient(), batchCalls = 0
        api.batch = { _ in batchCalls += 1; return response }
        let store = makeStore(api, persistence: disk)
        await store.updateLocation(fix)
        let pin = store.displayedOptions[0]
        store.togglePin(pin)
        XCTAssertEqual(store.nearbyPins.map(\.id), [pin.id])
        store.clearArea()
        XCTAssertNil(store.center); XCTAssertNil(store.location)
        XCTAssertNil(store.walkingOrigin, "A pinned route opened now has no walk to show")
        XCTAssertTrue(store.stops.isEmpty); XCTAssertTrue(store.displayedOptions.isEmpty); XCTAssertTrue(store.mapGroups.isEmpty)
        XCTAssertEqual(store.distantPins.map(\.id), [pin.id], "Pinned routes stay reachable")
        let calls = batchCalls
        await store.refreshAnswers(force: true)
        XCTAssertEqual(batchCalls, calls, "Nothing is requested for a place the rider may have left")
        let relaunched = makeStore(api, persistence: disk)
        XCTAssertNil(relaunched.center)
        XCTAssertTrue(relaunched.displayedOptions.isEmpty)
        XCTAssertEqual(relaunched.pins.map(\.id), [pin.id])
    }

    @MainActor func testPinsElsewhereFollowTheAreaCentreAndKeepNearbyRows() async {
        let disk = persistence()
        let viennaNearby = stop().lineSelections[0]
        let viennaElsewhere = StopLineSelection(stop: platform("vienna-outside-area", meters: 1_000), line: line, lineIndex: 0)
        let newYork = Coordinate(lat: 40.7128, lon: -74.0060)
        let newYorkElsewhere = StopLineSelection(
            stop: .init(id: "nyc-outside-area", name: "New York", type: .bus, lines: [],
                        location: .init(lat: 40.75, lon: -73.99), distance: nil),
            line: line, lineIndex: 0)
        disk.savePins([newYorkElsewhere, viennaElsewhere, viennaNearby])
        let store = makeStore(persistence: disk)

        XCTAssertNil(store.center)
        XCTAssertEqual(store.distantPins.map(\.id), [newYorkElsewhere.id, viennaElsewhere.id, viennaNearby.id])

        await store.loadArea(coordinate)
        XCTAssertEqual(store.nearbyPins.map(\.id), [viennaNearby.id])
        XCTAssertTrue(store.displayedOptions.contains(viennaNearby))
        XCTAssertEqual(store.distantPins.map(\.id), [viennaElsewhere.id])
        let restored = makeStore(persistence: disk)
        XCTAssertEqual(restored.distantPins.map(\.id), [viennaElsewhere.id])

        await store.loadArea(newYork)
        XCTAssertTrue(store.nearbyPins.isEmpty)
        XCTAssertEqual(store.distantPins.map(\.id), [newYorkElsewhere.id])

        store.clearArea()
        XCTAssertEqual(store.distantPins.map(\.id), [newYorkElsewhere.id, viennaElsewhere.id, viennaNearby.id])
    }

    @MainActor func testPinsElsewhereRespectThe50KilometreBoundary() async {
        let origin = Coordinate(lat: 0, lon: 0)
        let inside = NearbyStop(id: "inside", name: "Inside", type: .bus, lines: [],
                                location: .init(lat: 0, lon: 0.44915), distance: nil)
        let outside = NearbyStop(id: "outside", name: "Outside", type: .bus, lines: [],
                                 location: .init(lat: 0, lon: 0.44917), distance: nil)
        let invalid = NearbyStop(id: "invalid", name: "Invalid", type: .bus, lines: [],
                                 location: .init(lat: 91, lon: 0), distance: nil)
        XCTAssertGreaterThan(origin.distance(to: inside.location), 49_998)
        XCTAssertLessThan(origin.distance(to: inside.location), 50_000)
        XCTAssertGreaterThan(origin.distance(to: outside.location), 50_000)
        XCTAssertLessThan(origin.distance(to: outside.location), 50_002)
        let store = makeStore()
        store.togglePin(.init(stop: inside, line: line, lineIndex: 0))
        store.togglePin(.init(stop: outside, line: line, lineIndex: 0))
        store.togglePin(.init(stop: invalid, line: line, lineIndex: 0))
        XCTAssertEqual(store.distantPins.count, 3)

        await store.loadArea(origin)
        XCTAssertEqual(store.distantPins.map { $0.stop.id }, [inside.id])
    }

    @MainActor func testShortcutsOfferAndResolvePinsFromEveryCity() async throws {
        let suite = "departs.tests.\(UUID())"
        let disk = persistence(suite: suite)
        let vienna = stop().lineSelections[0]
        let newYork = StopLineSelection(
            stop: .init(id: "nyc", name: "New York", type: .bus, lines: [],
                        location: .init(lat: 40.7128, lon: -74.0060), distance: nil),
            line: line, lineIndex: 0)
        disk.savePins([vienna, newYork])
        let store = makeStore(persistence: disk)
        await store.loadArea(coordinate)
        XCTAssertTrue(store.distantPins.isEmpty)

        let query = PinnedRouteQuery(defaultsSuiteName: suite)
        let suggested = try await query.suggestedEntities()
        let resolved = try await query.entities(for: [newYork.id])
        XCTAssertEqual(suggested.map(\.id), [vienna.id, newYork.id])
        XCTAssertEqual(resolved.map(\.id), [newYork.id])
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
        api.stops = { _ in nearbyCalls += 1; return [] }
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

    @MainActor func testBadgeColumnTakesEveryListedLineIncludingPins() async throws {
        let disk = persistence(), stops = try sampleStops(), response = try sampleBatch()
        // Pin a line that would otherwise be listed only under its stop.
        let pin = StopLineSelection(stop: stops[11], line: response.boards.first { $0.stopId == "77704_3233" }!.groups[0].line, lineIndex: 0)
        disk.savePins([pin])
        let store = makeStore(try sampleClient(), persistence: disk)
        await store.loadArea(coordinate)
        let lines = BadgeColumn.lines(in: store.displayedOptions)
        XCTAssertEqual(lines.map(\.name), ["U3", "13A", "49", "48A", "14A"], "Pins first, then list order, once per line")
        XCTAssertEqual(Set(lines.map(\.lineIdentity)).count, lines.count)
        XCTAssertEqual(Set(lines.map(\.lineIdentity)), Set(store.displayedOptions.map { $0.line.lineIdentity }))
    }

    @MainActor func testBadgeColumnIsAsWideAsTheWidestBadge() {
        let lines = [LineInfo(name: "U3", direction: "a", type: .subway), LineInfo(name: "48A", direction: "b", type: .bus),
                     LineInfo(name: "49", direction: "c", type: .tram), LineInfo(name: "N71", direction: "d", type: .bus)]
        func width(_ view: some View) -> CGFloat {
            UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
        }
        let widths = lines.map { width(LineBadge(line: $0).fixedSize()) }
        XCTAssertGreaterThan(Set(widths).count, 1, "The sample needs badges of different widths")
        XCTAssertEqual(width(BadgeColumn.Stack(lines: lines).fixedSize()), widths.max()!, accuracy: 0.5)
        XCTAssertEqual(width(BadgeColumn.Stack(lines: Array(lines.reversed())).fixedSize()), widths.max()!, accuracy: 0.5,
                       "Order and rendering never change the column")
    }

    func testLinesShowOnlyTheirNumberAndLetterIdentifier() {
        let cases: [(String, String)] = [
            ("FlixBus N70", "N70"), ("13A", "13A"), ("U3", "U3"), ("N70", "N70"), ("  M2 ", "M2"),
            ("S 1", "S 1"), ("RE 5", "RE 5"), ("Bus 200", "200"), ("Bus N8 Nachtlinie", "N8"),
            ("FEX", "FEX"), ("Airport Express", "Airport Express")
        ]
        for (name, shown) in cases {
            XCTAssertEqual(LineInfo(name: name, direction: "x", type: .bus).shortName, shown, name)
        }
        let flix = LineInfo(name: "FlixBus N70", direction: "Prague", type: .bus)
        XCTAssertEqual(flix.id, "FlixBus N70::Prague", "Identity keeps the provider's name")
        XCTAssertEqual(flix.lineIdentity.name, "FlixBus N70")
    }

    @MainActor func testABrandedLineTakesNoMoreBadgeRoomThanItsIdentifier() {
        func width(_ view: some View) -> CGFloat {
            UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
        }
        let branded = LineInfo(name: "FlixBus N70", direction: "Prague", type: .bus)
        let plain = LineInfo(name: "N70", direction: "Prague", type: .bus)
        XCTAssertEqual(width(LineBadge(line: branded).fixedSize()), width(LineBadge(line: plain).fixedSize()), accuracy: 0.5)
        XCTAssertEqual(width(BadgeColumn.Stack(lines: [branded, LineInfo(name: "13A", direction: "x", type: .bus)]).fixedSize()),
                       width(BadgeColumn.Stack(lines: [plain, LineInfo(name: "13A", direction: "x", type: .bus)]).fixedSize()), accuracy: 0.5)
    }

    @MainActor func testHomeMapCentresOnPreciseLiveLocationOnlyWithAUsableFix() {
        let map = StopsMapView.Coordinator()
        let saved = CLLocationCoordinate2D(latitude: 48.2, longitude: 16.34)
        let live = CLLocationCoordinate2D(latitude: 48.201, longitude: 16.35)
        func location(accuracy: CLLocationAccuracy) -> CLLocation {
            CLLocation(coordinate: live, altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: .now)
        }
        XCTAssertNil(map.target, "No location and no saved area: no centre and no ring")
        map.fallback = saved
        XCTAssertEqual(map.target?.latitude, saved.latitude)
        map.receiveLive(location(accuracy: 10))
        XCTAssertEqual(map.target?.latitude, saved.latitude, "Without a usable fix the app stays on the saved area")
        map.followsLive = true
        XCTAssertEqual(map.target?.latitude, live.latitude, "A precise live location moves the map")
        map.receiveLive(location(accuracy: 800))
        XCTAssertEqual(map.target?.latitude, saved.latitude, "A coarse location never moves the map")
        map.receiveLive(location(accuracy: -1))
        XCTAssertEqual(map.target?.latitude, saved.latitude)
        XCTAssertEqual(StopsMapView.span, 960)
    }

    @MainActor func testHomeMapDrawsNoRingAndKeepsItsFraming() {
        XCTAssertFalse(StopsMapView.showsRing, "The owner had the ring hidden (O23)")
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let coordinator = StopsMapView.Coordinator()
        coordinator.fallback = CLLocationCoordinate2D(latitude: 48.20134, longitude: 16.34941)
        coordinator.frame(map)
        XCTAssertTrue(map.overlays.isEmpty, "No circle around the rider")
        XCTAssertEqual(map.region.center.latitude, 48.20134, accuracy: 0.0005, "The map still centres on the rider")
        coordinator.fallback = nil
        coordinator.frame(map)
        XCTAssertTrue(map.overlays.isEmpty)
    }

    func testLineCountdownColumnTakesOnlyTheCountdownsShown() {
        let shown = [departure(0.5), departure(4), departure(10), departure(16)]
        XCTAssertEqual(CountdownColumn.texts(shown, fresh: true, now: instant), ["Now", "4 min", "10 min", "16 min"])
        XCTAssertEqual(CountdownColumn.texts(shown, fresh: false, now: instant), [], "Saved times show clocks, outside the column")
        XCTAssertEqual(CountdownColumn.texts([departure(4), departure(75)], fresh: true, now: instant), ["4 min"],
                       "A departure beyond the hour shows its clock alone")
    }

    @MainActor func testLineCountdownColumnIsAsWideAsTheWidestCountdown() {
        func width(_ view: some View) -> CGFloat {
            UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 1000, height: 1000)).width
        }
        let texts = ["4 min", "10 min", "Now", "16 min"]
        let widths = texts.map { width(Text($0).font(CountdownColumn.font).monospacedDigit().fixedSize()) }
        XCTAssertGreaterThan(widths[1], widths[0] + 4, "Two digits are wider than one")
        XCTAssertEqual(width(CountdownColumn.Stack(texts: texts).fixedSize()), widths.max()!, accuracy: 0.5)
        XCTAssertEqual(width(CountdownColumn.Stack(texts: ["4 min", "6 min"]).fixedSize()), widths[0], accuracy: 0.5,
                       "One-digit countdowns need no wider column")
    }

    func testWalkButtonOpensAppleMapsWithoutAChoiceWhenGoogleMapsIsMissing() {
        let disk = persistence()
        let choice = MapAppChoice(persistence: disk) { _ in false }
        XCTAssertFalse(choice.offersChoice)
        XCTAssertEqual(choice.tap(), .open(.apple), "Without Google Maps the button opens Apple Maps, as before")
        disk.saveMapApp(.google)
        XCTAssertEqual(choice.tap(), .open(.apple), "A remembered Google Maps that was removed is not used")
        XCTAssertNil(disk.loadMapApp(), "and is forgotten")
    }

    func testWalkButtonAsksFirstThenRemembersTheChoice() {
        let disk = persistence()
        var installed = true
        let choice = MapAppChoice(persistence: disk) { $0.scheme == "comgooglemaps" && installed }
        XCTAssertTrue(choice.offersChoice)
        XCTAssertEqual(choice.tap(), .showChoice, "The first tap offers the choice")
        choice.choose(.google)
        XCTAssertEqual(choice.tap(), .open(.google), "Afterwards a tap opens what was used last time")
        XCTAssertEqual(MapAppChoice(persistence: TransitPersistence(defaults: disk.defaults)) { _ in true }.tap(), .open(.google),
                       "The choice survives a relaunch")
        choice.choose(.apple)
        XCTAssertEqual(choice.tap(), .open(.apple))
        choice.choose(.google)
        installed = false
        XCTAssertEqual(choice.tap(), .open(.apple), "Google Maps removed: Apple Maps, no choice")
        installed = true
        XCTAssertEqual(choice.tap(), .showChoice, "Reinstalled: as if nothing was remembered")
    }

    func testGoogleMapsOpensWalkingDirectionsToTheStop() {
        let stop = NearbyStop(id: "x", name: "Neubaugasse", type: .bus, lines: [], location: .init(lat: 48.198081, lon: 16.350874), distance: nil)
        XCTAssertEqual(MapAppChoice.googleURL(for: stop).absoluteString, "comgooglemaps://?daddr=48.198081,16.350874&directionsmode=walking")
        XCTAssertEqual(MapApp.allCases.map(\.name), ["Apple Maps", "Google Maps"])
    }

    func testAWrappedStopLineNeverStartsWithADot() {
        let line = StopLine.walk(stop: "Burggasse/Neubaugasse", walk: "5 min walk", distance: "350 m")
        XCTAssertEqual(line, "Burggasse/Neubaugasse\u{00A0}· 5 min walk\u{00A0}· 350 m")
        XCTAssertFalse(line.contains(" ·"), "A breaking space before a dot would let a line start with it")
        XCTAssertEqual(StopLine.fromThisArea(stop: "Siebensterngasse"), "Siebensterngasse\u{00A0}· from this area")
    }

    func testHomeMapReachesTheTopOnlyOnATallStatusBarAtStandardTextSizes() {
        XCTAssertEqual(MapStrip.height(statusBar: 62, accessibilitySize: false), 62, "Dynamic Island")
        XCTAssertEqual(MapStrip.height(statusBar: 47, accessibilitySize: false), 47, "Notch")
        XCTAssertEqual(MapStrip.height(statusBar: 20, accessibilitySize: false), 0, "An iPhone SE keeps the square alone")
        XCTAssertEqual(MapStrip.height(statusBar: 62, accessibilitySize: true), 0,
                       "At accessibility sizes the map is a list row and scrolls away")
    }

    @MainActor func testHomeMapTakesNoTouchUnderTheStatusBar() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        // Guarantees a strip even on a device whose own status bar is short.
        controller.additionalSafeAreaInsets.top = 30
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let map = HomeMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 420))
        controller.view.addSubview(map)
        window.layoutIfNeeded()
        let strip = map.safeAreaInsets.top
        XCTAssertGreaterThanOrEqual(strip, 30, "The map lies under the status bar")
        XCTAssertNil(map.hitTest(CGPoint(x: 160, y: strip / 2), with: nil), "Nothing under the status bar can be tapped")
        XCTAssertNil(map.hitTest(CGPoint(x: 160, y: strip - 1), with: nil))
        XCTAssertNotNil(map.hitTest(CGPoint(x: 160, y: strip + 1), with: nil), "The square below takes touches as before")
    }

    @MainActor func testResizedIPadRouteMapFitsTheLatestRegion() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.traitOverrides.userInterfaceIdiom = .pad
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let map = MKMapView()
        let container = RouteMapView.MapContainerView(mapView: map)
        controller.view.addSubview(container)
        container.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        container.layoutIfNeeded()
        var route = MKCoordinateRegion(center: .init(latitude: 48.2, longitude: 16.3),
                                       latitudinalMeters: 800, longitudinalMeters: 800)
        container.fittedRegion = route
        container.frame.size = CGSize(width: 500, height: 320)
        container.layoutIfNeeded()
        // An update arrives after layout has queued its refit.
        route.center.longitude += 1
        container.fittedRegion = route
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(map.centerCoordinate.latitude, route.center.latitude, accuracy: 0.0001)
        XCTAssertEqual(map.centerCoordinate.longitude, route.center.longitude, accuracy: 0.0001)
    }

    @MainActor func testLineMapTakesNoTouchUnderTheStatusBar() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.additionalSafeAreaInsets.top = 30
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let map = RouteMapView.MapContainerView(mapView: MKMapView())
        map.frame = CGRect(x: 0, y: 0, width: 320, height: 420)
        controller.view.addSubview(map)
        window.layoutIfNeeded()
        let strip = map.safeAreaInsets.top
        XCTAssertGreaterThanOrEqual(strip, 30, "The line map lies under the status bar")
        XCTAssertNil(map.hitTest(CGPoint(x: 160, y: strip - 1), with: nil), "Nothing under the status bar can be touched (A26)")
        XCTAssertNotNil(map.hitTest(CGPoint(x: 160, y: strip + 1), with: nil), "The map below the strip still accepts taps")
    }

    func testAMapBadgeStandsForItsLineInEveryDirection() {
        func row(_ name: String, _ direction: String, _ type: TransportType = .bus) -> StopLineSelection {
            .init(stop: stop(), line: LineInfo(name: name, direction: direction, type: type), lineIndex: 0)
        }
        // The owner's stop of 19 November: 13A one way, 46 both ways.
        let stopWithBoth = TransitStore.StopGroup(id: "s", name: "Strozzigasse", stops: [stop()], active: [
            row("13A", "Hauptbahnhof"), row("46", "Joachimsthalerplatz", .tram), row("46", "Parlament/Volkstheater", .tram)])
        XCTAssertEqual(NearbyStopsView.rows(for: .line(0), in: stopWithBoth).map(\.line.direction), ["Hauptbahnhof"],
                       "One direction: the badge opens its line")
        XCTAssertEqual(NearbyStopsView.rows(for: .line(1), in: stopWithBoth).map(\.line.direction),
                       ["Joachimsthalerplatz", "Parlament/Volkstheater"], "Two directions: both are offered")
        XCTAssertEqual(NearbyStopsView.rows(for: .whole, in: stopWithBoth).count, 3, "VoiceOver activates the stop: every row")
        XCTAssertEqual(NearbyStopsView.rows(for: .line(5), in: stopWithBoth).count, 3, "A badge that is gone falls back to the stop")
        XCTAssertEqual(NearbyStopsView.rows(for: .more, in: stopWithBoth).count, 3, "So does +N when every line has a badge")
        // Five lines: three badges and "+2".
        let hub = TransitStore.StopGroup(id: "h", name: "Hub", stops: [stop()], active: [
            row("1", "A"), row("2", "B"), row("2", "C"), row("3", "D"), row("4", "E"), row("5", "F"), row("5", "G")])
        XCTAssertEqual(NearbyStopsView.rows(for: .line(1), in: hub).map(\.line.direction), ["B", "C"])
        XCTAssertEqual(NearbyStopsView.rows(for: .line(2), in: hub).map(\.line.direction), ["D"])
        XCTAssertEqual(NearbyStopsView.rows(for: .more, in: hub).map(\.line.direction), ["E", "F", "G"],
                       "+N stands for the lines without a badge")
    }

    @MainActor func testATouchOnALabelFindsItsBadge() {
        func label(_ names: [String]) -> MapLineAnnotationView {
            let view = MapLineAnnotationView(annotation: nil, reuseIdentifier: nil)
            view.configure(lines: names.map { LineInfo(name: $0, direction: "x", type: .bus) })
            return view
        }
        let two = label(["13A", "46"])
        let first = two.rect(of: .line(0)), second = two.rect(of: .line(1))
        XCTAssertLessThan(first.maxX, second.minX)
        XCTAssertGreaterThanOrEqual(two.bounds.height, 44)
        XCTAssertEqual(two.part(at: CGPoint(x: first.midX, y: 1)), .line(0), "Above the badge, inside the 44-point region")
        XCTAssertEqual(two.part(at: CGPoint(x: second.midX, y: two.bounds.midY)), .line(1))
        XCTAssertEqual(two.part(at: CGPoint(x: 0, y: two.bounds.midY)), .line(0), "The margin belongs to the nearest badge")
        XCTAssertEqual(two.part(at: CGPoint(x: two.bounds.maxX, y: two.bounds.midY)), .line(1))
        let five = label(["1", "2", "3", "4", "5"])
        XCTAssertEqual(five.part(at: CGPoint(x: five.rect(of: .line(2)).midX, y: five.bounds.midY)), .line(2))
        XCTAssertEqual(five.part(at: CGPoint(x: five.rect(of: .more).midX, y: five.bounds.midY)), .more)
        XCTAssertEqual(five.rect(of: .whole).minX, five.rect(of: .line(0)).minX, accuracy: 0.5)
        XCTAssertEqual(five.rect(of: .whole).maxX, five.rect(of: .more).maxX, accuracy: 0.5)
        XCTAssertEqual(label(["7"]).part(at: .zero), .line(0))
    }

    @MainActor func testVoiceOverActivatesTheStopNotOneBadge() throws {
        let coordinator = StopsMapView.Coordinator()
        let map = HomeMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 320))
        map.delegate = coordinator
        let rows = ["Joachimsthalerplatz", "Parlament/Volkstheater"].map {
            StopLineSelection(stop: stop(), line: LineInfo(name: "46", direction: $0, type: .tram), lineIndex: 0)
        }
        let pin = StopsMapView.StopAnnotation(group: .init(id: "strozzi", name: "Strozzigasse", stops: [stop()], active: rows))
        map.addAnnotation(pin)
        let label = try XCTUnwrap(coordinator.mapView(map, viewFor: pin) as? MapLineAnnotationView)
        let reported = expectation(description: "The stop is reported as a whole")
        coordinator.onTap = { stop, part, _ in
            XCTAssertEqual(stop, "strozzi")
            XCTAssertEqual(part, .whole)
            reported.fulfill()
        }
        XCTAssertTrue(label.accessibilityActivate(), "The label handles its own activation")
        wait(for: [reported], timeout: 2)
    }

    @MainActor func testTheDirectionChoiceFitsItsNamesAndWrapsALongOne() {
        func size(_ directions: [String]) -> CGSize {
            let rows = directions.map { StopLineSelection(stop: stop(), line: LineInfo(name: "46", direction: $0, type: .tram), lineIndex: 0) }
            let choice = MapDirections(rows: rows, direction: { $0.line.direction }, onPick: { _ in })
            return UIHostingController(rootView: choice).sizeThatFits(in: CGSize(width: 1000, height: 1000))
        }
        let short = size(["Dornbach", "Friedrich-Engels-Platz"])
        XCTAssertLessThan(short.width, 280, "As wide as its longest direction")
        XCTAssertGreaterThanOrEqual(short.height, 88, "Two rows of at least 44 points")
        XCTAssertLessThan(size(["Dornbach", "Ottakring"]).width, short.width)
        let long = size(["Kaiserebersdorf, Zinnergasse über Hauptbahnhof und Simmering", "Ottakring"])
        XCTAssertEqual(long.width, MapDirections.widthLimit, accuracy: 0.5, "A long direction stops at the limit")
        XCTAssertGreaterThan(long.height, short.height, "and wraps instead")
        XCTAssertEqual(MapDirections.spoken(LineInfo(name: "46", direction: "WIEN DORNBACH", type: .tram)), "Tram 46 toward Wien Dornbach",
                       "Spoken without a time, like what is shown")
    }

    func testNearbyURLAlwaysAsksForFourHundredMetres() throws {
        let url = try APIService.nearbyStopsURL(lat: 48.2, lon: 16.3)
        XCTAssertEqual(url.host, "api.departs.now")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "radius" }?.value, "400")
        XCTAssertEqual(TransitStore.radius, 400)
    }

}

final class WalkingRouteServiceTests: XCTestCase {
    private let origin = Coordinate(lat: 48.20134, lon: 16.34941)
    private let destination = Coordinate(lat: 48.202, lon: 16.35)

    private func polyline(_ coordinates: [Coordinate]) -> MKPolyline {
        MKPolyline(coordinates: coordinates.map(\.clLocationCoordinate2D), count: coordinates.count)
    }

    @MainActor func testWalkingRequestMapsPolylineAndMetrics() async throws {
        let corner = Coordinate(lat: origin.lat, lon: destination.lon)
        let polyline = polyline([origin, corner, destination])
        let service = WalkingRouteService(start: { request, complete in
            XCTAssertEqual(request.transportType, .walking)
            XCTAssertFalse(request.requestsAlternateRoutes)
            XCTAssertEqual(request.source?.location.coordinate.latitude, self.origin.lat)
            XCTAssertEqual(request.source?.location.coordinate.longitude, self.origin.lon)
            XCTAssertEqual(request.destination?.location.coordinate.latitude, self.destination.lat)
            XCTAssertEqual(request.destination?.location.coordinate.longitude, self.destination.lon)
            complete(.success((polyline, 195, 234)))
            return {}
        })

        let route = try await service.route(from: origin, to: destination)
        XCTAssertEqual(route.duration, 195)
        XCTAssertEqual(route.distance, 234)
        XCTAssertEqual(route.geometry.type, "LineString")
        XCTAssertEqual(route.geometry.coordinates.count, 3)
        for (point, expected) in zip(route.geometry.coordinates, [origin, corner, destination]) {
            XCTAssertEqual(point[0], expected.lon, accuracy: 1e-8)
            XCTAssertEqual(point[1], expected.lat, accuracy: 1e-8)
        }
    }

    @MainActor func testRejectsInvalidMetricsAndShortPolyline() throws {
        let valid = polyline([origin, destination])
        let short = polyline([origin])
        let invalid: [WalkingRouteService.RouteData] = [
            (valid, .nan, 1), (valid, .infinity, 1), (valid, -1, 1),
            (valid, 1, .nan), (valid, 1, .infinity), (valid, 1, -1), (short, 1, 1),
        ]
        for (polyline, duration, distance) in invalid {
            XCTAssertThrowsError(try WalkingRouteService.walkingRoute(polyline: polyline, duration: duration, distance: distance))
        }
        XCTAssertNoThrow(try WalkingRouteService.walkingRoute(polyline: valid, duration: 0, distance: 0))
    }

    @MainActor func testReusesOnlyExactEndpointsForOneHour() async throws {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var requests = 0
        let polyline = polyline([origin, destination])
        let service = WalkingRouteService(now: { date }, start: { _, complete in
            requests += 1
            complete(.success((polyline, Double(requests), 234)))
            return {}
        })

        let initial = try await service.route(from: origin, to: destination)
        _ = try await service.route(from: origin, to: origin)
        _ = try await service.route(from: destination, to: destination)
        date += 3_599
        let cached = try await service.route(from: origin, to: destination)
        XCTAssertEqual(cached, initial)
        XCTAssertEqual(requests, 3)
        date += 1
        let expired = try await service.route(from: origin, to: destination)
        XCTAssertEqual(expired.duration, 4)
    }

    @MainActor func testIdenticalRequestsShareOneCalculationAndEitherWaiterCanCancel() async throws {
        let probe = WalkingProbe()
        let service = WalkingRouteService(start: probe.start)
        let started = expectation(description: "shared calculation")
        probe.onStart = { _ in started.fulfill() }
        let first = Task { try await service.route(from: origin, to: destination) }
        await fulfillment(of: [started], timeout: 2)
        let joining = expectation(description: "second caller")
        let second = Task {
            joining.fulfill()
            return try await service.route(from: origin, to: destination)
        }
        await fulfillment(of: [joining], timeout: 2)
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertEqual(probe.started, 1)
        XCTAssertEqual(probe.cancelled, [])
        probe.complete(0)
        let route = try await second.value
        XCTAssertEqual(route.duration, 180)
    }

    @MainActor func testCancellingLastCallerCancelsMapKitCalculation() async throws {
        let probe = WalkingProbe()
        let service = WalkingRouteService(start: probe.start)
        let started = expectation(description: "calculation started")
        probe.onStart = { _ in started.fulfill() }
        let route = Task { try await service.route(from: origin, to: destination) }
        await fulfillment(of: [started], timeout: 2)
        route.cancel()
        do { _ = try await route.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertEqual(probe.cancelled, [0])
        XCTAssertEqual(probe.active, 0)
    }

    @MainActor func testStalledCalculationTimesOutAndCancelsMapKit() async throws {
        let probe = WalkingProbe()
        let sleeping = expectation(description: "timeout started")
        let clock = AsyncGate()
        let service = WalkingRouteService(sleep: { interval in
            XCTAssertEqual(interval, .seconds(12))
            sleeping.fulfill()
            try await clock.wait()
        }, start: probe.start)
        let route = Task { try await service.route(from: origin, to: destination) }
        await fulfillment(of: [sleeping], timeout: 2)
        clock.resume()
        do { _ = try await route.value; XCTFail("Expected timeout") }
        catch let error as URLError { XCTAssertEqual(error.code, .timedOut) }
        XCTAssertEqual(probe.cancelled, [0])
        XCTAssertEqual(probe.active, 0)
    }

    @MainActor func testCacheEvictsOldestAndDropsExpiredEntriesOnRead() async throws {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var requests = 0
        var fail = false
        let polyline = polyline([origin, destination])
        let service = WalkingRouteService(now: { date }, start: { _, complete in
            requests += 1
            complete(fail ? .failure(MKError(.directionsNotFound)) : .success((polyline, Double(requests), 234)))
            return {}
        })
        let count = WalkingRouteService.cacheCapacity
        for index in 0...count {
            let point = Coordinate(lat: destination.lat, lon: destination.lon + Double(index) / 1000)
            _ = try await service.route(from: origin, to: point)
            date += 1
        }
        let newest = Coordinate(lat: destination.lat, lon: destination.lon + Double(count) / 1000)
        let kept = try await service.route(from: origin, to: newest)
        XCTAssertEqual(kept.duration, Double(count + 1))
        let evicted = try await service.route(from: origin, to: destination)
        XCTAssertEqual(evicted.duration, Double(count + 2))

        let savedTime = date
        date += 3_600
        fail = true
        do { _ = try await service.route(from: origin, to: newest); XCTFail("Expected a miss") }
        catch let error as MKError { XCTAssertEqual(error.code, .directionsNotFound) }
        date = savedTime
        fail = false
        let pruned = try await service.route(from: origin, to: newest)
        XCTAssertEqual(pruned.duration, Double(count + 4))
    }

    @MainActor func testQueuedWalkDoesNotStartWhenProviderAuthorizationIsRevoked() async throws {
        var allowed = true
        let probe = WalkingProbe()
        let service = WalkingRouteService(isAuthorized: { allowed }, start: probe.start)
        let active = expectation(description: "three active calculations")
        active.expectedFulfillmentCount = 3
        let released = expectation(description: "every waiter fails")
        released.expectedFulfillmentCount = 4
        probe.onStart = { _ in active.fulfill() }
        let routes = (0..<4).map { index in
            Task {
                defer { released.fulfill() }
                do {
                    _ = try await service.route(from: origin,
                                                to: .init(lat: destination.lat, lon: destination.lon + Double(index) / 1000))
                    XCTFail("A revoked waiter must fail")
                } catch {
                    XCTAssertTrue(error is CancellationError)
                }
            }
        }
        defer { for route in routes { route.cancel() } }
        await fulfillment(of: [active], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(service.pendingRequestCount, 4)
        allowed = false
        probe.onStart = nil
        probe.complete(0)
        await fulfillment(of: [released], timeout: 2)
        XCTAssertEqual(probe.started, 3)
        XCTAssertEqual(probe.active, 0)
        XCTAssertEqual(service.pendingRequestCount, 0)

        allowed = true
        let restarted = expectation(description: "a new authorized request can use a slot")
        probe.onStart = { _ in restarted.fulfill() }
        let newRoute = Task { try await service.route(from: origin, to: destination) }
        defer { newRoute.cancel() }
        await fulfillment(of: [restarted], timeout: 2)
        probe.complete(3)
        _ = try await newRoute.value
        XCTAssertEqual(service.pendingRequestCount, 0)
    }

    @MainActor func testCacheEvictionFollowsInsertionOrderAfterBackwardClockChange() async throws {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var requests = 0
        let polyline = polyline([origin, destination])
        let service = WalkingRouteService(now: { date }, start: { _, complete in
            requests += 1
            complete(.success((polyline, Double(requests), 220)))
            return {}
        })
        let destinations = (0...WalkingRouteService.cacheCapacity).map { index in
            Coordinate(lat: destination.lat, lon: destination.lon + Double(index) / 1000)
        }
        for (index, point) in destinations.enumerated() {
            if index == WalkingRouteService.cacheCapacity - 1 { date -= 60 }
            _ = try await service.route(from: origin, to: point)
            date += 1
        }
        let penultimate = destinations[destinations.count - 2]
        let retained = try await service.route(from: origin, to: penultimate)
        XCTAssertEqual(retained.duration, 32)
        let evicted = try await service.route(from: origin, to: destinations[0])
        XCTAssertEqual(evicted.duration, 34)
    }

}


@MainActor
private final class WalkingProbe {
    var onStart: ((Int) -> Void)?
    private(set) var destinations: [Coordinate] = []
    private var completions: [WalkingRouteService.Completion] = []
    private var running: Set<Int> = []
    private(set) var cancelled: [Int] = []
    private(set) var peak = 0
    var started: Int { completions.count }
    var active: Int { running.count }

    func start(_ request: MKDirections.Request, _ completion: @escaping WalkingRouteService.Completion) -> () -> Void {
        let index = completions.count
        if let coordinate = request.destination?.location.coordinate {
            destinations.append(.init(lat: coordinate.latitude, lon: coordinate.longitude))
        }
        completions.append(completion)
        running.insert(index)
        peak = max(peak, running.count)
        onStart?(index)
        return {
            self.running.remove(index)
            self.cancelled.append(index)
        }
    }

    func complete(_ index: Int, duration: Double = 180) {
        running.remove(index)
        let coordinates = [CLLocationCoordinate2D(latitude: 48.2, longitude: 16.3),
                           CLLocationCoordinate2D(latitude: 48.21, longitude: 16.3)]
        completions[index](.success((MKPolyline(coordinates: coordinates, count: 2), duration, 220)))
    }
}

@MainActor
private final class AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async throws {
        try Task.checkCancellation()
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
    }

    func resume() {
        let waiting = continuation
        continuation = nil
        waiting?.resume()
    }
}
