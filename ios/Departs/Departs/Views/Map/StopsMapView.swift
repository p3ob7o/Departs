import SwiftUI
import MapKit

struct StopsMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D
    let stops: [NearbyStop]
    let stopColors: [String: Color]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.stopColors = stopColors

        // Update region centered on user
        let region = MKCoordinateRegion(
            center: userCoordinate,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        map.setRegion(region, animated: false)

        // Remove old annotations
        let existing = map.annotations.filter { !($0 is MKUserLocation) }
        map.removeAnnotations(existing)

        // Add user dot
        let userPin = StopAnnotation(
            coordinate: userCoordinate,
            stopId: "__user__",
            transportLabel: "",
            isUser: true
        )
        map.addAnnotation(userPin)

        // Add stop pins
        for stop in stops {
            let pin = StopAnnotation(
                coordinate: stop.location.clLocationCoordinate2D,
                stopId: stop.id,
                transportLabel: stop.type.label,
                isUser: false
            )
            map.addAnnotation(pin)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(stopColors: stopColors)
    }

    final class StopAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let stopId: String
        let transportLabel: String
        let isUser: Bool

        init(coordinate: CLLocationCoordinate2D, stopId: String, transportLabel: String, isUser: Bool) {
            self.coordinate = coordinate
            self.stopId = stopId
            self.transportLabel = transportLabel
            self.isUser = isUser
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var stopColors: [String: Color]

        init(stopColors: [String: Color]) {
            self.stopColors = stopColors
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? StopAnnotation else { return nil }

            if pin.isUser {
                return userDotView(for: pin, in: mapView)
            } else {
                return stopPinView(for: pin, in: mapView)
            }
        }

        private func userDotView(for annotation: StopAnnotation, in mapView: MKMapView) -> MKAnnotationView {
            let id = "UserDot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation

            let size: CGFloat = 24
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            dot.backgroundColor = .clear

            // Halo
            let halo = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
            halo.layer.cornerRadius = size / 2
            dot.addSubview(halo)

            // Inner dot
            let inner = UIView(frame: CGRect(x: 6, y: 6, width: 12, height: 12))
            inner.backgroundColor = .systemBlue
            inner.layer.cornerRadius = 6
            inner.layer.borderColor = UIColor.white.cgColor
            inner.layer.borderWidth = 2
            inner.layer.shadowColor = UIColor.black.cgColor
            inner.layer.shadowOpacity = 0.3
            inner.layer.shadowOffset = .zero
            inner.layer.shadowRadius = 2
            dot.addSubview(inner)

            // Pulse animation
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1.0
            pulse.toValue = 1.3
            pulse.duration = 2.0
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            halo.layer.add(pulse, forKey: "pulse")

            let fadeAnim = CABasicAnimation(keyPath: "opacity")
            fadeAnim.fromValue = 0.2
            fadeAnim.toValue = 0.1
            fadeAnim.duration = 2.0
            fadeAnim.autoreverses = true
            fadeAnim.repeatCount = .infinity
            fadeAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            halo.layer.add(fadeAnim, forKey: "fade")

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(dot)
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.centerOffset = .zero
            return view
        }

        private func stopPinView(for annotation: StopAnnotation, in mapView: MKMapView) -> MKAnnotationView {
            let id = "StopPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation

            let size: CGFloat = 28
            let circle = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))

            let uiColor: UIColor
            if let color = stopColors[annotation.stopId] {
                uiColor = UIColor(color)
            } else {
                uiColor = .systemGray
            }

            circle.backgroundColor = uiColor
            circle.layer.cornerRadius = size / 2
            circle.layer.borderColor = UIColor.white.cgColor
            circle.layer.borderWidth = 2
            circle.layer.shadowColor = UIColor.black.cgColor
            circle.layer.shadowOpacity = 0.3
            circle.layer.shadowOffset = CGSize(width: 0, height: 1)
            circle.layer.shadowRadius = 1.5

            let label = UILabel(frame: circle.bounds)
            label.text = annotation.transportLabel
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13, weight: .bold)
            label.textColor = .white
            circle.addSubview(label)

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(circle)
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.centerOffset = .zero
            return view
        }
    }
}

#Preview {
    StopsMapView(
        userCoordinate: PreviewData.userCoordinate.clLocationCoordinate2D,
        stops: PreviewData.stops,
        stopColors: Dictionary(uniqueKeysWithValues: PreviewData.stops.enumerated().map {
            ($0.element.id, StopPalette.color(at: $0.offset))
        })
    )
    .frame(height: 400)
}
