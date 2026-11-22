import Foundation
import SwiftUI

struct TransitClient {
    var stops: (Coordinate) async throws -> [NearbyStop]
    var departures: (StopLineSelection) async throws -> [Departure]
    var directions: (Coordinate, Coordinate) async throws -> WalkingRoute
    var batch: ([String]) async throws -> BatchDepartures

    static let live = TransitClient(
        stops: { try await APIService.shared.fetchNearbyStops(lat: $0.lat, lon: $0.lon) },
        departures: { try await APIService.shared.fetchDepartures(stopId: $0.stop.id, line: $0.line) },
        directions: { try await APIService.shared.fetchDirections(from: $0, to: $1) },
        batch: { try await APIService.shared.fetchDepartureBoards(stopIDs: $0) }
    )
}

@MainActor
@Observable
final class TransitStore {
    typealias StopGroup = HomeStopGroup
    nonisolated static let runningHorizon: TimeInterval = 60 * 60
    nonisolated static let refreshInterval: TimeInterval = 25
    /// Departs looks this far around the rider, in metres, and nowhere else.
    nonisolated static let radius = 400
    /// Straight-line distance in metres for pins outside the nearby stops.
    private static let distantPinRadius: Double = 50_000

    /// Where the rider was when the list on screen was built: the centre of
    /// its circle. There is no other way to choose a place.
    private(set) var center: Coordinate?
    private(set) var location: LocationFix?
    private(set) var stops: [NearbyStop] = []
    private(set) var stopsCheckedAt: Date?
    private(set) var home = HomeSnapshot()
    private(set) var boards: [String: DepartureBoard] = [:]
    private(set) var walks: [String: CachedWalk] = [:]
    private(set) var pins: [StopLineSelection] = []
    private(set) var isLoadingStops = false
    private(set) var stopsError: String?
    private(set) var departuresError: String?
    private(set) var boardErrors: Set<String> = []
    private(set) var loadingBoards: Set<String> = []
    private(set) var areaRevision = 0
    private(set) var homeRestored = false

    @ObservationIgnored private let client: TransitClient
    @ObservationIgnored private let persistence: TransitPersistence
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var areaTask: Task<Void, Never>?
    @ObservationIgnored private var batchTask: Task<Void, Never>?
    @ObservationIgnored private var batchID: UUID?
    @ObservationIgnored private var lastBatchAttempt: Date?
    @ObservationIgnored private var lastResponse: BatchDepartures?
    @ObservationIgnored private var pendingHome: HomeSnapshot?
    @ObservationIgnored private var interactingPresentations: Set<String> = []
    @ObservationIgnored private var detailChecks: [String: Date] = [:]
    @ObservationIgnored private var detailBoardIDs: Set<String> = []
    @ObservationIgnored private var walkRequests: [String: (origin: Coordinate, id: UUID)] = [:]
    private var savedBoards: Set<String> = []

    init(client: TransitClient = .live, persistence: TransitPersistence = .init(), now: @escaping () -> Date = { .now }) {
        self.client = client
        self.persistence = persistence
        self.now = now
        persistence.removeRetiredData()
        pins = persistence.loadPins()
        boards = persistence.loadBoards().filter { $0.value.checkedAt.isRecent(at: now(), within: 86_400) }
        if let saved = persistence.loadNearby(), saved.center.isValid {
            center = saved.center
            stops = saved.stops
            stopsCheckedAt = saved.checkedAt
            if let savedHome = persistence.loadHome(), savedHome.checkedAt?.isRecent(at: now(), within: 86_400) == true,
               Set(savedHome.selections.map { $0.stop.id }).isSubset(of: Set(stops.map(\.id))) {
                home = savedHome
                homeRestored = true
                boards.merge(home.boards) { _, saved in saved }
            }
        }
        savedBoards = Set(boards.keys)
    }

    var groups: [StopGroup] { home.groups }
    var nearbyPins: [StopLineSelection] { home.pins }
    var distantPins: [StopLineSelection] {
        guard let center else { return pins }
        let ids = Set(stops.map(\.id))
        return pins.filter {
            !ids.contains($0.stop.id) && $0.stop.location.isValid
                && center.distance(to: $0.stop.location) <= Self.distantPinRadius
        }
    }
    var displayedOptions: [StopLineSelection] { home.selections }
    var mapGroups: [StopGroup] {
        guard let center else { return [] }
        return HomeSnapshot.physicalStops(stops, from: center).compactMap { group in
            let ids = Set(group.stops.map(\.id))
            var result = group
            result.active = home.selections.filter { ids.contains($0.stop.id) }
            return result.active.isEmpty ? nil : result
        }
    }
    /// The current position, else the centre of the last area, else nothing:
    /// a pinned route opened while location is off has no walk to show.
    var walkingOrigin: Coordinate? {
        if let location, location.isUsable(at: now()) { return location.coordinate }
        return center
    }

    func setInteracting(_ active: Bool, presentationID: String) {
        if active { interactingPresentations.insert(presentationID) }
        else { interactingPresentations.remove(presentationID); publishPendingHome() }
    }
    func clearPresentation(_ prefix: String) {
        interactingPresentations = interactingPresentations.filter { !$0.hasPrefix(prefix) }
        publishPendingHome()
    }
    func setPresentationActive(_ active: Bool, presentationID: String) {
        if !active { clearPresentation(presentationID) }
    }
    private func publish(_ snapshot: HomeSnapshot) {
        pendingHome = snapshot
        publishPendingHome()
    }
    private func publishPendingHome() {
        guard interactingPresentations.isEmpty, let pendingHome else { return }
        home = pendingHome
        self.pendingHome = nil
        persistence.saveHome(home)
        // Start routes for the list actually published, including a response
        // that had to wait until the rider stopped scrolling.
        Task { await self.refreshListedWalks() }
    }

    func isPinned(_ selection: StopLineSelection) -> Bool { pins.contains { $0.id == selection.id } }
    func togglePin(_ selection: StopLineSelection) {
        if let index = pins.firstIndex(where: { $0.id == selection.id }) { pins.remove(at: index) }
        else { pins.append(selection) }
        persistence.savePins(pins)
        if let response = lastResponse, let center, let date = TimeFormatter.parseISO(response.fetchedAt) {
            var snapshot = HomeSnapshot.make(stops: stops, origin: center, pins: pins, response: response, checkedAt: date)
            let current = pendingHome ?? home
            snapshot.missing = current.missing
            snapshot.boards.merge(current.boards) { _, current in current }
            publish(snapshot)
        } else {
            // Pin actions work on a saved list without requiring network access.
            var snapshot = pendingHome ?? home
            if isPinned(selection), stops.contains(where: { $0.id == selection.stop.id }) {
                snapshot.pins.append(selection)
                for index in snapshot.groups.indices {
                    snapshot.groups[index].active.removeAll { $0.line.serviceIdentity == selection.line.serviceIdentity }
                }
            } else if !isPinned(selection) {
                snapshot.pins.removeAll { $0.id == selection.id }
                if snapshot.boards[selection.id]?.hasDepartureWithinHorizon == true, let center {
                    if let index = snapshot.groups.firstIndex(where: { $0.stops.contains { $0.id == selection.stop.id } }) {
                        snapshot.groups[index].active.append(selection)
                    } else if var group = HomeSnapshot.physicalStops(stops, from: center)
                        .first(where: { $0.stops.contains { $0.id == selection.stop.id } }) {
                        group.active = [selection]
                        snapshot.groups.append(group)
                        snapshot.groups.sort { $0.distance(from: center) < $1.distance(from: center) }
                    }
                }
            }
            snapshot.groups.removeAll { $0.active.isEmpty && !$0.hasMissingBoard }
            publish(snapshot)
        }
    }

    func updateLocation(_ fix: LocationFix, showing selection: StopLineSelection? = nil, force: Bool = false) async {
        guard fix.coordinate.isValid else { return }
        location = fix
        if let selection { await refreshSelection(selection, force: force); return }
        guard let center, center.distance(to: fix.coordinate) <= 150 else {
            await loadArea(fix.coordinate)
            return
        }
        // Same place. Two fixes at one spot never match exactly, so the centre
        // stays: a new one would empty the list and move the map for nothing.
        if stopsCheckedAt?.isRecent(at: now(), within: 300) != true { await loadArea(center) }
        else { await refreshAnswers(force: force) }
    }

    /// Load the stops within reach of a point. A different point is a new
    /// area: the list starts over and the map recentres.
    func loadArea(_ newCenter: Coordinate, forceRefresh: Bool = false) async {
        guard newCenter.isValid else { return }
        let changed = center != newCenter
        if !changed, let areaTask { await areaTask.value; return }
        if changed { resetArea() }
        center = newCenter
        let revision = areaRevision
        isLoadingStops = true
        stopsError = nil
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if revision == self.areaRevision { self.isLoadingStops = false; self.areaTask = nil } }
            do {
                let response = try await self.client.stops(newCenter)
                guard revision == self.areaRevision, !Task.isCancelled else { return }
                var seen: Set<String> = []
                self.stops = Array(response.filter {
                    $0.location.isValid && $0.location.distance(to: newCenter) <= Double(Self.radius)
                        && seen.insert($0.id).inserted
                }.prefix(50))
                self.stopsCheckedAt = self.now()
                if self.stops.isEmpty {
                    self.home = .init()
                    self.pendingHome = nil
                    self.lastResponse = nil
                    self.persistence.saveHome(self.home)
                }
                self.persistence.saveNearby(.init(center: newCenter, stops: self.stops, checkedAt: self.now()))
                self.isLoadingStops = false
                await self.refreshAnswers(force: forceRefresh || changed)
            } catch {
                guard revision == self.areaRevision, !Self.cancelled(error) else { return }
                if changed || self.stopsCheckedAt == nil {
                    self.stopsError = String(localized: "Couldn't update nearby stops")
                } else {
                    // The stops already listed still stand. Keep their times moving.
                    self.isLoadingStops = false
                    await self.refreshAnswers(force: forceRefresh)
                }
            }
        }
        areaTask = task
        await task.value
    }

    /// Location is off, so there is no "around you". Forget the last area
    /// instead of refreshing a place the rider may have left. Pins stay.
    func clearArea() {
        guard center != nil || location != nil else { return }
        resetArea()
        center = nil
        location = nil
        isLoadingStops = false
        stopsError = nil
        persistence.clearNearby()
    }

    private func resetArea() {
        areaRevision += 1
        areaTask?.cancel()
        areaTask = nil
        batchTask?.cancel()
        batchTask = nil
        batchID = nil
        lastBatchAttempt = nil
        lastResponse = nil
        pendingHome = nil
        home = .init()
        stops = []
        stopsCheckedAt = nil
        departuresError = nil
        homeRestored = false
        persistence.saveHome(home)
    }

    func refreshAnswers(force: Bool = false) async {
        guard let center, !stops.isEmpty else { return }
        if let batchTask { await batchTask.value; return }
        if !force, lastBatchAttempt?.isRecent(at: now(), within: Self.refreshInterval) == true { return }
        let revision = areaRevision, requestID = UUID(), requestedStops = stops
        batchID = requestID
        lastBatchAttempt = now()
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.batchID == requestID { self.batchTask = nil }
            }
            do {
                let response = try await self.client.batch(requestedStops.map(\.id))
                guard revision == self.areaRevision, !Task.isCancelled else { return }
                guard let fetchedAt = TimeFormatter.parseISO(response.fetchedAt) else { throw APIError.requestFailed }
                var snapshot = HomeSnapshot.make(stops: requestedStops, origin: center, pins: self.pins,
                                                 response: response, checkedAt: fetchedAt)
                let previous = self.pendingHome ?? self.home
                if !snapshot.missing.isEmpty, previous.checkedAt != nil {
                    // Partial results update known times, never promote or move
                    // saved rows. A complete response can select a new list.
                    var retained = previous
                    retained.missing = snapshot.missing
                    retained.checkedAt = fetchedAt
                    for selection in previous.selections {
                        if !snapshot.missing.contains(selection.stop.id), let board = snapshot.boards[selection.id] {
                            retained.boards[selection.id] = board
                        } else { retained.missing.insert(selection.stop.id) }
                    }
                    snapshot = retained
                } else { self.lastResponse = response }
                // Home supplies the initial two times. Once a line requests
                // its own board, a home refresh must not replace its four-time
                // board or certify a failed detail request.
                for (id, board) in snapshot.boards where !self.detailBoardIDs.contains(id) {
                    self.boards[id] = board
                }
                for selection in snapshot.selections {
                    if snapshot.missing.contains(selection.stop.id) {
                        self.savedBoards.insert(selection.id)
                    } else if !self.detailBoardIDs.contains(selection.id) {
                        self.boardErrors.remove(selection.id)
                        self.savedBoards.remove(selection.id)
                    }
                }
                self.homeRestored = false
                self.departuresError = nil
                self.publish(snapshot)
                self.persistence.saveBoards(self.boards)
            } catch {
                guard revision == self.areaRevision, !Self.cancelled(error) else { return }
                self.departuresError = String(localized: "Couldn't update departures")
                // Opening a line after a failed home refresh must keep its
                // cached times saved until the per-line request succeeds.
                self.savedBoards.formUnion(self.home.selections.map(\.id))
            }
        }
        batchTask = task
        await task.value
    }

    func isHomeBoardFresh(for selection: StopLineSelection, at date: Date) -> Bool {
        !homeRestored && departuresError == nil && !home.missing.contains(selection.stop.id)
            && home.boards[selection.id]?.isFresh(at: date) == true
    }
    func needsListRefresh(at date: Date) -> Bool {
        homeRestored || departuresError != nil || !home.missing.isEmpty
            || home.checkedAt.map { !$0.isRecent(at: date, within: 60) } == true
            || home.selections.contains { !isHomeBoardFresh(for: $0, at: date) }
    }

    func refreshSelection(_ selection: StopLineSelection, force: Bool = false) async {
        async let route: Void = refreshWalk(for: selection.stop)
        await refreshBoard(selection, force: force)
        await route
    }
    func refreshBoard(_ selection: StopLineSelection, force: Bool = false) async {
        let key = selection.id
        guard !loadingBoards.contains(key) else { return }
        if !force, detailChecks[key]?.isRecent(at: now(), within: Self.refreshInterval) == true { return }
        loadingBoards.insert(key)
        detailBoardIDs.insert(key)
        detailChecks[key] = now()
        defer { loadingBoards.remove(key) }
        do {
            let departures = try await client.departures(selection)
            boards[key] = .init(departures: departures, checkedAt: now())
            boardErrors.remove(key)
            savedBoards.remove(key)
            persistence.saveBoards(boards)
        } catch {
            if Self.cancelled(error) { detailChecks[key] = nil }
            else { boardErrors.insert(key) }
        }
    }
    func isBoardFresh(for selection: StopLineSelection, at date: Date) -> Bool {
        boards[selection.id]?.isFresh(at: date) == true && !boardErrors.contains(selection.id) && !savedBoards.contains(selection.id)
    }
    func walk(for stop: NearbyStop, at date: Date = .now) -> CachedWalk? {
        guard let origin = walkingOrigin, let walk = walks[stop.id], walk.matches(origin, at: date) else { return nil }
        return walk
    }
    func walk(for group: StopGroup, at date: Date) -> CachedWalk? {
        guard let center, let platform = group.nearestPlatform(to: center) else { return nil }
        return walk(for: platform, at: date)
    }
    private func refreshListedWalks() async {
        guard let center else { return }
        let platforms = mapGroups.compactMap { $0.nearestPlatform(to: center) }
        await withTaskGroup(of: Void.self) { group in
            var iterator = platforms.makeIterator()
            for _ in 0..<3 {
                if let stop = iterator.next() { group.addTask { await self.refreshWalk(for: stop) } }
            }
            while await group.next() != nil {
                if let stop = iterator.next() { group.addTask { await self.refreshWalk(for: stop) } }
            }
        }
    }
    private func refreshWalk(for stop: NearbyStop) async {
        guard let origin = walkingOrigin, origin.distance(to: stop.location) < 5000 else { return }
        if walks[stop.id]?.matches(origin, at: now()) == true { return }
        if let pending = walkRequests[stop.id], pending.origin.distance(to: origin) <= 40 { return }
        let requestID = UUID()
        walkRequests[stop.id] = (origin, requestID)
        defer {
            if walkRequests[stop.id]?.id == requestID { walkRequests[stop.id] = nil }
        }
        do {
            let route = try await client.directions(origin, stop.location)
            guard let currentOrigin = walkingOrigin, origin.distance(to: currentOrigin) <= 40 else { return }
            walks[stop.id] = .init(origin: origin, route: route, checkedAt: now())
        } catch { /* A walking failure never hides departure information. */ }
    }
    private static func cancelled(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
    }
}
