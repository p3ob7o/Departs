import Foundation
import SwiftUI

@Observable
final class NearbyStopsViewModel {
    private(set) var stops: [NearbyStop] = []
    private(set) var isLoading = false
    private(set) var error: String?

    var stopColors: [String: Color] {
        Dictionary(uniqueKeysWithValues: stops.enumerated().map { index, stop in
            (stop.id, StopPalette.color(at: index))
        })
    }

    @MainActor
    func loadStops(near coordinate: Coordinate) async {
        isLoading = true
        error = nil
        do {
            stops = try await APIService.shared.fetchNearbyStops(lat: coordinate.lat, lon: coordinate.lon)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}
