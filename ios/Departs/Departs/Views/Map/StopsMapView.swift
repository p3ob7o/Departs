import SwiftUI
import MapKit

struct StopsMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D
    let stops: [NearbyStop]
    let stopColors: [String: Color]
    var radius: Int = 400
    var selectedStopID: String? = nil
    var onSelect: (String) -> Void = { _ in }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = true
        map.isZoomEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = true
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.stopColors = stopColors
        context.coordinator.onSelect = onSelect

        if !Self.coordinatesEqual(context.coordinator.regionCenter, userCoordinate) || context.coordinator.radius != radius {
            let region = MKCoordinateRegion(
                center: userCoordinate,
                latitudinalMeters: Double(radius) * 2.4,
                longitudinalMeters: Double(radius) * 2.4
            )
            map.setRegion(region, animated: false)
            context.coordinator.regionCenter = userCoordinate
            context.coordinator.radius = radius
            map.removeOverlays(map.overlays)
            map.addOverlay(MKCircle(center: userCoordinate, radius: CLLocationDistance(radius)))
        }

        Self.syncStopAnnotations(on: map, stops: stops)
        if let selected = map.annotations.compactMap({ $0 as? StopAnnotation }).first(where: { $0.stopId == selectedStopID }),
           !map.selectedAnnotations.contains(where: { ($0 as? StopAnnotation)?.stopId == selected.stopId }) {
            context.coordinator.restoringSelection = true
            map.selectAnnotation(selected, animated: false)
            context.coordinator.restoringSelection = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(stopColors: stopColors)
    }

    final class StopAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let stopId: String
        let transportLabel: String
        var spokenLabel = ""
        var mode: TransportType = .tram
        let isUser: Bool

        init(coordinate: CLLocationCoordinate2D, stopId: String, transportLabel: String, isUser: Bool) {
            self.coordinate = coordinate
            self.stopId = stopId
            self.transportLabel = transportLabel
            self.isUser = isUser
        }
    }

    private static func syncStopAnnotations(on map: MKMapView, stops: [NearbyStop]) {
        var stopsByID: [String: NearbyStop] = [:]
        for stop in stops {
            stopsByID[stop.id] = stop
        }

        let existingPins = map.annotations.compactMap { $0 as? StopAnnotation }
        for pin in existingPins {
            guard
                let stop = stopsByID[pin.stopId],
                pin.transportLabel == (stop.lines.first?.name ?? stop.type.label),
                coordinatesEqual(pin.coordinate, stop.location.clLocationCoordinate2D)
            else {
                map.removeAnnotation(pin)
                continue
            }
        }

        let existingIDs = Set(map.annotations.compactMap { ($0 as? StopAnnotation)?.stopId })
        for stop in stops where !existingIDs.contains(stop.id) {
            let pin = StopAnnotation(
                coordinate: stop.location.clLocationCoordinate2D,
                stopId: stop.id,
                transportLabel: stop.lines.first?.name ?? stop.type.label,
                isUser: false
            )
            pin.spokenLabel = "\(stop.name), \(stop.type.displayName), \(stop.lines.map { $0.name + " toward " + $0.direction }.joined(separator: ", "))"
            pin.mode = stop.type
            map.addAnnotation(pin)
        }
    }

    private static func coordinatesEqual(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        guard let lhs else { return false }
        return coordinatesEqual(lhs, rhs)
    }

    private static func coordinatesEqual(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < 0.000001 &&
            abs(lhs.longitude - rhs.longitude) < 0.000001
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (String) -> Void = { _ in }
        var stopColors: [String: Color]
        var regionCenter: CLLocationCoordinate2D?
        var radius: Int?
        var restoringSelection = false

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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if !restoringSelection, let pin = view.annotation as? StopAnnotation, !pin.isUser {
                onSelect(pin.stopId)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = .systemBlue
            renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08)
            renderer.lineWidth = 2
            return renderer
        }

        private func userDotView(for annotation: StopAnnotation, in mapView: MKMapView) -> MKAnnotationView {
            let id = "UserDot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.isAccessibilityElement = true
            view.accessibilityLabel = annotation.spokenLabel
            view.accessibilityTraits = .button
            view.accessibilityIdentifier = "stop-map-pin"

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
            view.isAccessibilityElement = true
            view.accessibilityLabel = annotation.spokenLabel
            view.accessibilityTraits = .button
            view.accessibilityIdentifier = "stop-map-pin"

            let badge = MapLineBadge(name: annotation.transportLabel, type: annotation.mode,
                                     color: stopColors[annotation.stopId] ?? StopPalette.modeColor(annotation.mode))

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(badge)
            view.frame = badge.bounds
            view.centerOffset = .zero
            return view
        }
    }
}

/// Shared line-number and mode-symbol treatment for both MapKit wrappers.
final class MapLineBadge: UIView {
    init(name: String, type: TransportType, color: Color) {
        let label = UILabel()
        label.text = name
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        label.sizeToFit()
        let symbolSize = UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 13)
        let width = max(44, label.bounds.width + symbolSize + 19)
        let height = max(44, label.bounds.height + 8)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        backgroundColor = UIColor(color)
        layer.cornerRadius = 6
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 2
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 1.5
        let symbol = UIImageView(image: UIImage(systemName: type.symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize)))
        symbol.tintColor = .white
        symbol.contentMode = .scaleAspectFit
        symbol.frame = CGRect(x: 6, y: 4, width: symbolSize, height: height - 8)
        addSubview(symbol)
        label.frame = CGRect(x: symbolSize + 10, y: 4, width: width - symbolSize - 16, height: height - 8)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

#if DEBUG
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
#endif
