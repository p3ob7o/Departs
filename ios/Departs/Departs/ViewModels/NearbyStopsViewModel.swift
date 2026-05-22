import Foundation
import SwiftUI

@Observable
final class NearbyStopsViewModel {
    typealias NearbyStopsFetcher = (Double, Double) async throws -> [NearbyStop]

    private(set) var stops: [NearbyStop] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var stopColors: [String: Color] = [:]

    @MainActor
    func loadStops(near coordinate: Coordinate) async {
        await loadStops(near: coordinate) { lat, lon in
            try await APIService.shared.fetchNearbyStops(lat: lat, lon: lon)
        }
    }

    @MainActor
    func loadStops(near coordinate: Coordinate, fetch: NearbyStopsFetcher) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let loadedStops = try await fetch(coordinate.lat, coordinate.lon)
            stops = loadedStops
            stopColors = Self.makeStopColors(for: loadedStops)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func makeStopColors(for stops: [NearbyStop]) -> [String: Color] {
        Dictionary(uniqueKeysWithValues: stops.enumerated().map { index, stop in
            (stop.id, StopPalette.color(at: index))
        })
    }
}
