import Foundation
import SwiftUI

struct TransitClient {
    var stops: (Coordinate, Int) async throws -> [NearbyStop]
    var departures: (StopLineSelection) async throws -> [Departure]
    var directions: (Coordinate, Coordinate) async throws -> WalkingRoute

    static let live = TransitClient(
        stops: { try await APIService.shared.fetchNearbyStops(lat: $0.lat, lon: $0.lon, radius: $1) },
        departures: { try await APIService.shared.fetchDepartures(stopId: $0.stop.id, line: $0.line) },
        directions: { try await APIService.shared.fetchDirections(from: $0, to: $1) }
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
    private var restoredBoards: Set<String> = []
    var favoritesOnly = false
    var followsLocation = true
    private(set) var visibleLimit = 6

    @ObservationIgnored private let client: TransitClient
    @ObservationIgnored private let persistence: TransitPersistence
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var areaRevision = 0
    @ObservationIgnored private var walkRequests: [String: UUID] = [:]
    @ObservationIgnored private var walkingFrom: [String: Coordinate] = [:]

    init(client: TransitClient = .live, persistence: TransitPersistence = .init(), now: @escaping () -> Date = { .now }) {
        self.client = client
        self.persistence = persistence
        self.now = now
        pins = persistence.loadPins()
        boards = persistence.loadBoards().filter { $0.value.checkedAt.isRecent(at: now(), within: 86_400) }
        restoredBoards = Set(boards.keys)
        if let saved = persistence.loadNearby(), saved.area.coordinate.isValid {
            area = saved.area
            radius = [400, 800, 1600].contains(saved.radius) ? saved.radius : 400
            stops = saved.stops
            stopsCheckedAt = saved.checkedAt
        }
    }

    var selections: [StopLineSelection] {
        if favoritesOnly { return pins }
        let options = stops.flatMap(\.lineSelections)
        let pinnedIDs = Set(pins.map(\.id))
        return options.filter { pinnedIDs.contains($0.id) } + options.filter { !pinnedIDs.contains($0.id) }
    }

    var visibleSelections: [StopLineSelection] { Array(selections.prefix(visibleLimit)) }
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

    func showMore() { visibleLimit += 6 }

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
        guard let area, canSearchFarther else { return }
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
            visibleLimit = 6
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
        let options = visibleSelections
        async let routes: Void = refreshWalks(for: options)
        await runBatches(options) { await self.refreshBoard($0, force: force) }
        await routes
    }

    func refreshSelection(_ selection: StopLineSelection, force: Bool = false) async {
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
            if boards.count > 80 {
                boards = Dictionary(uniqueKeysWithValues: boards.sorted { $0.value.checkedAt > $1.value.checkedAt }.prefix(40).map { ($0.key, $0.value) })
            }
            boardErrors.remove(key)
            restoredBoards.remove(key)
            persistence.saveBoards(boards)
        } catch {
            guard !Self.cancelled(error) else { return }
            boardErrors.insert(key)
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
