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
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        state = .requesting
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .denied || status == .restricted {
            state = .denied
        } else {
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if case .requesting = state {
                manager.requestLocation()
            }
        case .denied, .restricted:
            state = .denied
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        state = .located(Coordinate(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if case .requesting = state {
            state = .failed(error.localizedDescription)
        }
    }
}
