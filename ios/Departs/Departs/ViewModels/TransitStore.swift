import Foundation
import SwiftUI

struct TransitClient {
    var stops: (Coordinate, Int) async throws -> [NearbyStop]
    var departures: (StopLineSelection) async throws -> [Departure]
    var directions: (Coordinate, Coordinate) async throws -> WalkingRoute
    var batch: ([String]) async throws -> BatchDepartures

    static let live = TransitClient(
        stops: { try await APIService.shared.fetchNearbyStops(lat: $0.lat, lon: $0.lon, radius: $1) },
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

    private(set) var recentAreas: [SearchArea] = []
    private(set) var area: SearchArea?
    private(set) var location: LocationFix?
    private(set) var radius = 400
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
    var followsLocation = true

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
        recentAreas = persistence.loadRecentAreas()
        pins = persistence.loadPins()
        boards = persistence.loadBoards().filter { $0.value.checkedAt.isRecent(at: now(), within: 86_400) }
        if let saved = persistence.loadNearby(), saved.area.coordinate.isValid {
            area = saved.area
            followsLocation = saved.area.source == .location
            radius = [400, 800, 1600].contains(saved.radius) ? saved.radius : 400
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
        let ids = Set(stops.map(\.id))
        return pins.filter { !ids.contains($0.stop.id) }
    }
    var displayedOptions: [StopLineSelection] { home.selections }
    var mapGroups: [StopGroup] {
        guard let area else { return [] }
        return HomeSnapshot.physicalStops(stops, from: area.coordinate).compactMap { group in
            let ids = Set(group.stops.map(\.id))
            var result = group
            result.active = home.selections.filter { ids.contains($0.stop.id) }
            return result.active.isEmpty ? nil : result
        }
    }
    var canSearchFarther: Bool { area != nil && radius < 1600 }
    var walkingOrigin: Coordinate? {
        if let location, location.isUsable(at: now()) { return location.coordinate }
        return area?.coordinate
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
        if let response = lastResponse, let area, let date = TimeFormatter.parseISO(response.fetchedAt) {
            var snapshot = HomeSnapshot.make(stops: stops, origin: area.coordinate, pins: pins, response: response, checkedAt: date)
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
                if snapshot.boards[selection.id]?.hasDepartureWithinHorizon == true, let area {
                    if let index = snapshot.groups.firstIndex(where: { $0.stops.contains { $0.id == selection.stop.id } }) {
                        snapshot.groups[index].active.append(selection)
                    } else if var group = HomeSnapshot.physicalStops(stops, from: area.coordinate)
                        .first(where: { $0.stops.contains { $0.id == selection.stop.id } }) {
                        group.active = [selection]
                        snapshot.groups.append(group)
                        snapshot.groups.sort { $0.distance(from: area.coordinate) < $1.distance(from: area.coordinate) }
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
        guard followsLocation else { await refreshAnswers(force: force); return }
        let moved = area.map { $0.coordinate.distance(to: fix.coordinate) > 150 } ?? true
        if moved || area?.source != .location || stopsCheckedAt?.isRecent(at: now(), within: 300) != true {
            await loadArea(.init(coordinate: fix.coordinate, name: String(localized: "Near you"), source: .location), radius: radius)
        } else { await refreshAnswers(force: force) }
    }

    func searchFarther() async {
        guard let area, canSearchFarther, !isLoadingStops else { return }
        await loadArea(area, radius: radius == 400 ? 800 : 1600)
    }

    func loadArea(_ newArea: SearchArea, radius newRadius: Int = 400, forceRefresh: Bool = false) async {
        guard newArea.coordinate.isValid else { return }
        let changed = area != newArea || radius != newRadius
        if !changed, let areaTask { await areaTask.value; return }
        if changed {
            areaRevision += 1
            areaTask?.cancel()
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
        area = newArea
        followsLocation = newArea.source == .location
        radius = newRadius
        if newArea.source == .chosen {
            recentAreas.removeAll { $0.coordinate.distance(to: newArea.coordinate) < 40 && $0.name == newArea.name }
            recentAreas.insert(newArea, at: 0)
            recentAreas = Array(recentAreas.prefix(5))
            persistence.saveRecentAreas(recentAreas)
        }
        let revision = areaRevision
        isLoadingStops = true
        stopsError = nil
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if revision == self.areaRevision { self.isLoadingStops = false; self.areaTask = nil } }
            do {
                let response = try await self.client.stops(newArea.coordinate, newRadius)
                guard revision == self.areaRevision, !Task.isCancelled else { return }
                var seen: Set<String> = []
                self.stops = Array(response.filter {
                    $0.location.isValid && $0.location.distance(to: newArea.coordinate) <= Double(newRadius)
                        && seen.insert($0.id).inserted
                }.prefix(50))
                self.stopsCheckedAt = self.now()
                if self.stops.isEmpty {
                    self.home = .init()
                    self.pendingHome = nil
                    self.lastResponse = nil
                    self.persistence.saveHome(self.home)
                }
                self.persistence.saveNearby(.init(area: newArea, radius: newRadius, stops: self.stops, checkedAt: self.now()))
                self.isLoadingStops = false
                await self.refreshAnswers(force: forceRefresh || changed)
            } catch {
                guard revision == self.areaRevision, !Self.cancelled(error) else { return }
                self.stopsError = String(localized: "Couldn't update nearby stops. Try again or choose an area.")
            }
        }
        areaTask = task
        await task.value
    }

    func refreshAnswers(force: Bool = false) async {
        guard let area, !stops.isEmpty else { return }
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
                var snapshot = HomeSnapshot.make(stops: requestedStops, origin: area.coordinate, pins: self.pins,
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
        guard let area, let platform = group.nearestPlatform(to: area.coordinate) else { return nil }
        return walk(for: platform, at: date)
    }
    private func refreshListedWalks() async {
        guard let area else { return }
        let platforms = mapGroups.compactMap { $0.nearestPlatform(to: area.coordinate) }
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
