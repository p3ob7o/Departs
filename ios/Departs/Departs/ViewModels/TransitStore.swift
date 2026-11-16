import Foundation
import SwiftUI

struct TransitClient {
    var stops: (Coordinate, Int) async throws -> [NearbyStop]
    var departures: (StopLineSelection) async throws -> [Departure]
    var directions: (Coordinate, Coordinate) async throws -> WalkingRoute

    var grouped: ((String) async throws -> GroupedDepartures)? = nil

    static let live = TransitClient(
        stops: { try await APIService.shared.fetchNearbyStops(lat: $0.lat, lon: $0.lon, radius: $1) },
        departures: { try await APIService.shared.fetchDepartures(stopId: $0.stop.id, line: $0.line) },
        directions: { try await APIService.shared.fetchDirections(from: $0, to: $1) },
        grouped: { try await APIService.shared.fetchGroupedDepartures(stopId: $0) }
    )
}

@MainActor
@Observable
final class TransitStore {
    private(set) var area: SearchArea?
    private(set) var location: LocationFix?
    private(set) var radius = 400
    private(set) var stops: [NearbyStop] = []
    private(set) var stopsCheckedAt: Date?
    private(set) var boards: [String: DepartureBoard] = [:]
    private(set) var walks: [String: CachedWalk] = [:]
    private(set) var pins: [StopLineSelection] = []
    private(set) var isLoadingStops = false
    private(set) var stopsError: String?
    private(set) var boardErrors: Set<String> = []
    private(set) var loadingBoards: Set<String> = []
    private(set) var loadingWalks: Set<String> = []
    private(set) var groups: [StopGroup] = []
    nonisolated static let runningHorizon: TimeInterval = 60 * 60
    nonisolated static let refreshInterval: TimeInterval = 25
    var interacting = false {
        didSet { if !interacting { rebuildGroups() } }
    }
    private var demandedStops: [NearbyStop] = []
    private var pendingStopIDs: Set<String> = []
    private var forcedStopIDs: Set<String> = []
    private var stopAttempts: [String: Date] = [:]
    private var visibleStops: [String: [NearbyStop]] = [:]
    private var hasMeasuredVisibility = false
    private var groupedUnavailable = false
    private var restoredBoards: Set<String> = []
    var followsLocation = true

    @ObservationIgnored private let client: TransitClient
    @ObservationIgnored private let persistence: TransitPersistence
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var areaRevision = 0
    @ObservationIgnored private var walkRequests: [String: UUID] = [:]
    @ObservationIgnored private var walkingFrom: [String: Coordinate] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var walkLoadTask: Task<Void, Never>?
    private var demandedWalks: [NearbyStop] = []
    private var pendingWalkIDs: Set<String> = []

    init(client: TransitClient = .live, persistence: TransitPersistence = .init(), now: @escaping () -> Date = { .now }) {
        self.client = client
        self.persistence = persistence
        self.now = now
        pins = persistence.loadPins()
        boards = persistence.loadBoards().filter { $0.value.checkedAt.isRecent(at: now(), within: 86_400) }
        restoredBoards = Set(boards.keys)
        if let saved = persistence.loadNearby(), saved.area.coordinate.isValid {
            area = saved.area
            followsLocation = saved.area.source == .location
            radius = [400, 800, 1600].contains(saved.radius) ? saved.radius : 400
            stops = saved.stops
            stopsCheckedAt = saved.checkedAt
        }
        rebuildGroups()
    }

    struct StopGroup: Identifiable {
        let id: String
        let name: String
        var stops: [NearbyStop]
        var options: [StopLineSelection] { stops.flatMap(\.lineSelections) }
        var active: [StopLineSelection] = []
        var idle: [StopLineSelection] = []
    }

    var nearbyPins: [StopLineSelection] {
        let ids = Set(stops.flatMap(\.lineSelections).map(\.id))
        return pins.filter { ids.contains($0.id) }
    }
    var distantPins: [StopLineSelection] {
        let ids = Set(stops.flatMap(\.lineSelections).map(\.id))
        return pins.filter { !ids.contains($0.id) }
    }

    private func rebuildGroups() {
        guard !interacting else { return }
        var result: [StopGroup] = []
        for stop in stops {
            if let index = result.firstIndex(where: { $0.name == stop.name && $0.stops[0].location.distance(to: stop.location) <= 150 }) {
                result[index].stops.append(stop)
            } else {
                result.append(.init(id: stop.id, name: stop.name, stops: [stop]))
            }
        }
        // Publish the partition together. Views never combine a deferred partition
        // with live board presence. Provider order stays fixed as walks arrive.
        groups = result.map { group in
            var group = group
            for option in group.options {
                if let board = boards[option.id], !boardErrors.contains(option.id),
                   board.coverageLimit != nil || !board.upcoming(at: board.checkedAt).contains(where: {
                       (TimeFormatter.parseISO($0.time)?.timeIntervalSince(board.checkedAt) ?? .infinity) <= Self.runningHorizon
                   }) {
                    group.idle.append(option)
                } else {
                    group.active.append(option)
                }
            }
            return group
        }
    }

    func loadGroup(_ group: StopGroup) async {
        demand(group.stops, force: false)
        await loadTask?.value
        await walkLoadTask?.value
    }

    func setVisible(_ stops: [NearbyStop], elementID: String, visible: Bool) {
        hasMeasuredVisibility = true
        if visible {
            visibleStops[elementID] = stops
            demand(stops, force: false)
        } else { visibleStops[elementID] = nil }
    }

    private func demand(_ stops: [NearbyStop], force: Bool) {
        demandWalks(stops)
        for stop in stops {
            guard !pendingStopIDs.contains(stop.id),
                  force || stopAttempts[stop.id]?.isRecent(at: now(), within: Self.refreshInterval) != true else { continue }
            pendingStopIDs.insert(stop.id)
            if force { forcedStopIDs.insert(stop.id) }
            demandedStops.append(stop)
            loadingBoards.formUnion(stop.lineSelections.map(\.id))
        }
        guard loadTask == nil, !demandedStops.isEmpty else { return }
        // Unstructured and store-owned: cancelling a row, location update or
        // navigation task must not cancel work another visible row needs.
        loadTask = Task { [weak self] in await self?.drainStops() }
    }

    private func drainStops() async {
        defer { loadTask = nil }
        while !demandedStops.isEmpty {
            let batch = Array(demandedStops.prefix(3))
            demandedStops.removeFirst(min(3, demandedStops.count))
            let forced = forcedStopIDs.intersection(batch.map(\.id))
            forcedStopIDs.subtract(forced)
            var legacy: [StopLineSelection] = []
            for stop in batch { stopAttempts[stop.id] = now() }
            await runBatches(batch.compactMap { $0.lineSelections.first }) { selection in
                let stop = selection.stop
                if let grouped = self.client.grouped, !self.groupedUnavailable {
                    do {
                        let response = try await grouped(stop.id)
                        for option in stop.lineSelections {
                            if let group = response.groups.first(where: { $0.line == option.line }) {
                                self.boards[option.id] = .init(departures: group.departures, checkedAt: self.now())
                                self.boardErrors.remove(option.id)
                                self.restoredBoards.remove(option.id)
                            } else if response.complete == true {
                                self.boards[option.id] = .init(departures: [], checkedAt: self.now())
                                self.boardErrors.remove(option.id)
                                self.restoredBoards.remove(option.id)
                            } else {
                                self.boards[option.id] = .init(departures: [], checkedAt: self.now(),
                                                              coverageLimit: .init(before: response.latestListedTime))
                                self.boardErrors.remove(option.id)
                                self.restoredBoards.remove(option.id)
                            }
                        }
                    } catch {
                        if case APIError.groupedUnavailable = error {
                            self.groupedUnavailable = true
                            legacy.append(contentsOf: stop.lineSelections)
                        } else if Self.cancelled(error) {
                            self.stopAttempts[stop.id] = nil
                        } else {
                            self.boardErrors.formUnion(stop.lineSelections.map(\.id))
                        }
                    }
                } else { legacy.append(contentsOf: stop.lineSelections) }
            }
            rebuildGroups()
            // Reserve loading flags for the per-line loader while retaining the
            // stop-level pending flag, so duplicate visibility events do not fan out.
            for option in legacy { loadingBoards.remove(option.id) }
            await runBatches(legacy) { await self.refreshBoard($0, force: forced.contains($0.stop.id)) }
            persistence.saveBoards(boards)
            for stop in batch {
                pendingStopIDs.remove(stop.id)
                loadingBoards.subtract(stop.lineSelections.map(\.id))
            }
            rebuildGroups()
        }
    }

    private func demandWalks(_ stops: [NearbyStop]) {
        for stop in stops where pendingWalkIDs.insert(stop.id).inserted { demandedWalks.append(stop) }
        guard walkLoadTask == nil, !demandedWalks.isEmpty else { return }
        walkLoadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.walkLoadTask = nil }
            while !self.demandedWalks.isEmpty {
                let batch = Array(self.demandedWalks.prefix(3))
                self.demandedWalks.removeFirst(batch.count)
                await self.refreshWalks(for: batch.flatMap(\.lineSelections))
                for stop in batch { self.pendingWalkIDs.remove(stop.id) }
            }
        }
    }
    var canSearchFarther: Bool { area != nil && radius < 1600 }

    var walkingOrigin: Coordinate? {
        if let location, location.isUsable(at: now()) { return location.coordinate }
        return area?.coordinate
    }

    func isPinned(_ selection: StopLineSelection) -> Bool { pins.contains { $0.id == selection.id } }

    func togglePin(_ selection: StopLineSelection) {
        if let index = pins.firstIndex(where: { $0.id == selection.id }) { pins.remove(at: index) }
        else { pins.append(selection) }
        persistence.savePins(pins)
    }

    func updateLocation(_ fix: LocationFix, showing selection: StopLineSelection? = nil, force: Bool = false) async {
        guard fix.coordinate.isValid else { return }
        location = fix
        if let selection { await refreshSelection(selection, force: force); return }
        guard followsLocation else { await refreshAnswers(force: force); return }
        let moved = area.map { $0.coordinate.distance(to: fix.coordinate) > 150 } ?? true
        let needsStops = moved || area?.source != .location || stopsCheckedAt?.isRecent(at: now(), within: 300) != true
        if needsStops {
            await loadArea(.init(coordinate: fix.coordinate, name: "Near you", source: .location), radius: radius)
        } else {
            await refreshAnswers(force: force)
        }
    }

    func searchFarther() async {
        guard let area, canSearchFarther, !isLoadingStops else { return }
        await loadArea(area, radius: radius == 400 ? 800 : 1600)
    }

    func loadArea(_ newArea: SearchArea, radius newRadius: Int = 400, forceRefresh: Bool = false) async {
        guard newArea.coordinate.isValid else { return }
        areaRevision += 1
        let revision = areaRevision
        let differentArea = area.map { $0.coordinate.distance(to: newArea.coordinate) > 150 } ?? true
        if differentArea {
            stops = []
            stopsCheckedAt = nil
            visibleStops = [:]
            hasMeasuredVisibility = false
            for stop in demandedStops {
                pendingStopIDs.remove(stop.id)
                forcedStopIDs.remove(stop.id)
                loadingBoards.subtract(stop.lineSelections.map(\.id))
            }
            demandedStops = []
            for stop in demandedWalks { pendingWalkIDs.remove(stop.id) }
            demandedWalks = []
        }
        area = newArea
        followsLocation = newArea.source == .location
        radius = newRadius
        isLoadingStops = true
        stopsError = nil
        defer { if revision == areaRevision { isLoadingStops = false } }
        do {
            let response = try await client.stops(newArea.coordinate, newRadius)
            guard revision == areaRevision, !Task.isCancelled else { return }
            var seen = Set<String>()
            let received = response.filter { seen.insert($0.id).inserted }
            // Keep existing rows in place during refresh; append newly discovered stops.
            let byID = Dictionary(received.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let oldIDs = Set(stops.map(\.id))
            stops = stops.compactMap { byID[$0.id] } + received.filter { !oldIDs.contains($0.id) }
            rebuildGroups()
            stopsCheckedAt = now()
            let refreshedSelections = Dictionary(uniqueKeysWithValues: stops.flatMap(\.lineSelections).map { ($0.id, $0) })
            pins = pins.map { refreshedSelections[$0.id] ?? $0 }
            persistence.savePins(pins)
            persistence.saveNearby(.init(area: newArea, radius: newRadius, stops: stops, checkedAt: now()))
            isLoadingStops = false
            await refreshAnswers(force: forceRefresh)
        } catch {
            guard revision == areaRevision, !Self.cancelled(error) else { return }
            stopsError = "Couldn't update nearby stops. Try again or choose an area."
        }
    }

    func refreshAnswers(force: Bool = false) async {
        demand(refreshTargets, force: force)
        await loadTask?.value
        await walkLoadTask?.value
    }

    var displayedOptions: [StopLineSelection] { refreshTargets.flatMap(\.lineSelections) }

    private var refreshTargets: [NearbyStop] {
        let visibleIDs = Set(visibleStops.values.flatMap { $0 }.map(\.id))
        let onScreen = hasMeasuredVisibility ? stops.filter { visibleIDs.contains($0.id) } : Array(stops.prefix(3))
        var seen: Set<String> = []
        return (nearbyPins.map(\.stop) + onScreen).filter { seen.insert($0.id).inserted }
    }

    func refreshSelection(_ selection: StopLineSelection, force: Bool = false) async {
        if boards[selection.id]?.coverageLimit != nil, client.grouped != nil, !groupedUnavailable {
            demand([selection.stop], force: force)
            await loadTask?.value
            await walkLoadTask?.value
            return
        }
        async let route: Void = refreshWalk(for: selection.stop)
        await refreshBoard(selection, force: force)
        await route
    }

    func refreshBoard(_ selection: StopLineSelection, force: Bool = false) async {
        let key = selection.id
        guard !loadingBoards.contains(key) else { return }
        if !force, !boardErrors.contains(key), !restoredBoards.contains(key),
           boards[key]?.checkedAt.isRecent(at: now(), within: 25) == true { return }
        loadingBoards.insert(key)
        defer { loadingBoards.remove(key) }
        do {
            let departures = try await client.departures(selection)
            // This immutable service key is safe to cache even if the screen changed while loading.
            boards[key] = .init(departures: departures, checkedAt: now())
            // Keep all in-memory boards for the current browsing session.
            // TransitPersistence independently bounds its disk snapshot to 40.
            boardErrors.remove(key)
            restoredBoards.remove(key)
            persistence.saveBoards(boards)
            rebuildGroups()
        } catch {
            guard !Self.cancelled(error) else { stopAttempts[selection.stop.id] = nil; return }
            boardErrors.insert(key)
            rebuildGroups()
        }
    }

    func walk(for stop: NearbyStop, at date: Date = .now) -> CachedWalk? {
        guard let origin = walkingOrigin, let walk = walks[stop.id], walk.matches(origin, at: date) else { return nil }
        return walk
    }

    func advice(for selection: StopLineSelection, at date: Date = .now) -> DepartureAdvice {
        DepartureAdvice.make(board: boards[selection.id], walk: walk(for: selection.stop, at: date),
                             location: location, requestFailed: !isBoardFresh(for: selection, at: date), now: date)
    }

    func isBoardFresh(for selection: StopLineSelection, at date: Date) -> Bool {
        boards[selection.id]?.isFresh(at: date) == true && !boardErrors.contains(selection.id) && !restoredBoards.contains(selection.id)
    }

    func needsListRefresh(at date: Date) -> Bool {
        displayedOptions.contains { boardErrors.contains($0.id) || (boards[$0.id] != nil && !isBoardFresh(for: $0, at: date)) }
    }

    private func refreshWalks(for options: [StopLineSelection]) async {
        var seen = Set<String>()
        let unique = options.filter { seen.insert($0.stop.id).inserted }
        await runBatches(unique) { await self.refreshWalk(for: $0.stop) }
    }

    private func refreshWalk(for stop: NearbyStop) async {
        guard let origin = walkingOrigin, origin.distance(to: stop.location) < 5000 else { return }
        if walks[stop.id]?.matches(origin, at: now()) == true { return }
        if loadingWalks.contains(stop.id), let pendingOrigin = walkingFrom[stop.id], pendingOrigin.distance(to: origin) <= 40 { return }
        let requestID = UUID()
        walkRequests[stop.id] = requestID
        walkingFrom[stop.id] = origin
        loadingWalks.insert(stop.id)
        defer {
            if walkRequests[stop.id] == requestID {
                loadingWalks.remove(stop.id); walkRequests[stop.id] = nil; walkingFrom[stop.id] = nil
            }
        }
        do {
            let route = try await client.directions(origin, stop.location)
            guard let currentOrigin = walkingOrigin,
                  origin.distance(to: currentOrigin) <= 40 else { return }
            walks[stop.id] = .init(origin: origin, route: route, checkedAt: now())
            if walks.count > 80 {
                walks = Dictionary(uniqueKeysWithValues: walks.sorted { $0.value.checkedAt > $1.value.checkedAt }.prefix(40).map { ($0.key, $0.value) })
            }
        } catch { /* Departures remain useful without a walking route. */ }
    }

    // Each refresh limits departure and walking batches independently to three requests.
    private func runBatches(_ options: [StopLineSelection], action: @escaping @MainActor (StopLineSelection) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = options.makeIterator()
            for _ in 0..<3 {
                if let option = iterator.next() { group.addTask { await action(option) } }
            }
            while await group.next() != nil {
                guard !Task.isCancelled else { group.cancelAll(); break }
                if let option = iterator.next() { group.addTask { await action(option) } }
            }
        }
    }

    private static func cancelled(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
    }
}
