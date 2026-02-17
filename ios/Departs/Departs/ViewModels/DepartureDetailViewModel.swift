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

        async let depsTask = APIService.shared.fetchDepartures(stopId: stopId)
        async let routeTask = APIService.shared.fetchDirections(from: userCoord, to: stopCoord)

        do {
            let (deps, route) = try await (depsTask, routeTask)
            departures = deps
            walkingRoute = route
            isLoading = false
        } catch {
            // Try to at least show departures if directions fail
            do {
                departures = try await APIService.shared.fetchDepartures(stopId: stopId)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}
