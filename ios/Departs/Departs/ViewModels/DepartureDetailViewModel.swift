import Foundation

@Observable
final class DepartureDetailViewModel {
    typealias DeparturesFetcher = (String, LineInfo) async throws -> [Departure]
    typealias DirectionsFetcher = (Coordinate, Coordinate) async throws -> WalkingRoute

    private var loadID = UUID()

    private(set) var departures: [Departure] = []
    private(set) var walkingRoute: WalkingRoute?
    private(set) var isLoading = false
    private(set) var error: String?

    @MainActor
    func load(stopId: String, line: LineInfo, from userCoord: Coordinate, to stopCoord: Coordinate) async {
        await load(
            stopId: stopId,
            line: line,
            from: userCoord,
            to: stopCoord,
            fetchDepartures: { stopId, line in
                try await APIService.shared.fetchDepartures(stopId: stopId, line: line)
            },
            fetchDirections: { from, to in
                try await APIService.shared.fetchDirections(from: from, to: to)
            }
        )
    }

    @MainActor
    func load(
        stopId: String,
        line: LineInfo,
        from userCoord: Coordinate,
        to stopCoord: Coordinate,
        fetchDepartures: DeparturesFetcher,
        fetchDirections: DirectionsFetcher
    ) async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        error = nil
        departures = []
        walkingRoute = nil

        async let route = Self.fetchRouteIgnoringFailure(
            from: userCoord,
            to: stopCoord,
            fetchDirections: fetchDirections
        )

        do {
            let loadedDepartures = try await fetchDepartures(stopId, line)
            guard loadID == requestID, !Task.isCancelled else { return }
            departures = loadedDepartures
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }

        isLoading = false
        let loadedRoute = await route
        guard loadID == requestID, !Task.isCancelled else { return }
        walkingRoute = loadedRoute
    }

    private static func fetchRouteIgnoringFailure(
        from userCoord: Coordinate,
        to stopCoord: Coordinate,
        fetchDirections: DirectionsFetcher
    ) async -> WalkingRoute? {
        do {
            return try await fetchDirections(userCoord, stopCoord)
        } catch {
            return nil
        }
    }
}
