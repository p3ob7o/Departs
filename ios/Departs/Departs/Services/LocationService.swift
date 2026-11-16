import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case idle
        case requesting
        case located(Coordinate)
        case denied
        /// No fix in time, an error, or a fix too coarse to say what is within reach.
        case failed
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
            deny()
        } else {
            beginLocationRequest()
        }
    }

    private func deny() {
        timeout?.cancel()
        fix = nil
        state = .denied
    }

    private func beginLocationRequest() {
        timeout?.cancel()
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, case .requesting = self.state else { return }
            self.state = .failed
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
            deny()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard case .requesting = state, let location = locations.last,
              location.horizontalAccuracy >= 0,
              location.timestamp.isRecent(at: .now, within: 120) else { return }
        timeout?.cancel()
        let candidate = LocationFix(coordinate: Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
                                    capturedAt: location.timestamp, accuracy: location.horizontalAccuracy)
        // The store ignores a fix it cannot use. Reporting it as located would
        // leave home waiting for departures that are never requested.
        guard candidate.isUsable(at: .now) else { state = .failed; return }
        fix = candidate
        state = .located(candidate.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if case .requesting = state {
            timeout?.cancel()
            state = .failed
        }
    }
}
