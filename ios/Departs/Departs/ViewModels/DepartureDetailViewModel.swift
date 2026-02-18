import Foundation

@Observable
final class DepartureDetailViewModel {
    private(set) var departures: [Departure] = []
    private(set) var walkingRoute: WalkingRoute?
    private(set) var isLoading = false
    private(set) var error: String?

    @MainActor
    func load(stopId: String, from userCoord: Coordinate, to stopCoord: Coordinate) async {
        isLoading = true
        error = nil
        departures = []
        walkingRoute = nil

        // Load route and departures independently so the map updates immediately
        async let routeTask: Void = loadRoute(from: userCoord, to: stopCoord)
        async let depsTask: Void = loadDepartures(stopId: stopId)

        _ = await (routeTask, depsTask)
    }

    @MainActor
    private func loadRoute(from userCoord: Coordinate, to stopCoord: Coordinate) async {
        do {
            walkingRoute = try await APIService.shared.fetchDirections(from: userCoord, to: stopCoord)
        } catch {
            // Route is optional — map still shows user + stop without it
        }
    }

    @MainActor
    private func loadDepartures(stopId: String) async {
        do {
            departures = try await APIService.shared.fetchDepartures(stopId: stopId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
