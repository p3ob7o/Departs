import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case requesting
        case located(Coordinate)
        case denied
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var fix: LocationFix?
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        if case .requesting = state { return }
        state = .requesting
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .denied || status == .restricted {
            timeout?.cancel()
            state = .denied
        } else {
            beginLocationRequest()
        }
    }

    private func beginLocationRequest() {
        timeout?.cancel()
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, case .requesting = self.state else { return }
            self.state = .failed(String(localized: "Location is taking too long. Choose an area to continue."))
        }
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if case .requesting = state {
                beginLocationRequest()
            }
        case .denied, .restricted:
            timeout?.cancel()
            state = .denied
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard case .requesting = state, let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.timestamp.isRecent(at: .now, within: 120) else { return }
        timeout?.cancel()
        fix = LocationFix(coordinate: Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
                          capturedAt: location.timestamp, accuracy: location.horizontalAccuracy)
        state = .located(Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if case .requesting = state {
            timeout?.cancel()
            state = .failed(error.localizedDescription)
        }
    }
}
