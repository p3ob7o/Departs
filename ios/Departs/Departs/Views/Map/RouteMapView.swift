import SwiftUI
import MapKit

struct RouteMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D
    let stop: NearbyStop
    let stopColor: Color
    let walkingRoute: WalkingRoute?
    var line: LineInfo? = nil

    func makeUIView(context: Context) -> MapContainerView {
        let map = MKMapView()
        map.isScrollEnabled = true
        map.isZoomEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = true
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.delegate = context.coordinator
        return MapContainerView(mapView: map)
    }

    func updateUIView(_ container: MapContainerView, context: Context) {
        let map = container.mapView
        context.coordinator.stopColor = stopColor
        context.coordinator.stopType = line?.type ?? stop.type
        context.coordinator.stopName = stop.name
        context.coordinator.lineName = line?.name ?? stop.lines.first?.name ?? stop.type.label
        let routeCoordinates = walkingRoute?.geometry.clCoordinates ?? []
        let stopAnnotationKey = "\(stop.id)|\(stop.location.lat)|\(stop.location.lon)|\(context.coordinator.lineName)"

        if context.coordinator.stopAnnotationKey != stopAnnotationKey {
            let existing = map.annotations.filter { $0 is PinAnnotation }
            map.removeAnnotations(existing)

            let stopPin = PinAnnotation(
                coordinate: stop.location.clLocationCoordinate2D,
                kind: .stop
            )
            map.addAnnotation(stopPin)
            context.coordinator.stopAnnotationKey = stopAnnotationKey
        }

        let routeKey = Self.routeKey(for: routeCoordinates)
        if context.coordinator.routeKey != routeKey {
            map.removeOverlays(map.overlays)
            if routeCoordinates.count > 1 {
                let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
                map.addOverlay(polyline)
            }
            context.coordinator.routeKey = routeKey
        }

        // Fit region to user + stop (and route if available)
        var lats = [userCoordinate.latitude, stop.location.lat]
        var lons = [userCoordinate.longitude, stop.location.lon]
        for coord in routeCoordinates {
            lats.append(coord.latitude)
            lons.append(coord.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        // 1° lat ≈ 111km; min span ~150m = 0.00135°. Add 60% padding.
        let latSpan = max((lats.max()! - lats.min()!) * 1.6, 0.00135)
        let lonSpan = max((lons.max()! - lons.min()!) * 1.6, 0.002)
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )

        let regionKey = Self.regionKey(
            userCoordinate: userCoordinate,
            stopCoordinate: stop.location.clLocationCoordinate2D,
            routeKey: routeKey
        )
        if context.coordinator.regionKey != regionKey {
            context.coordinator.regionKey = regionKey
            container.targetRegion = region
            if map.bounds.size.width > 0 {
                container.targetRegion = nil
                map.setRegion(region, animated: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(stopColor: stopColor, stopType: stop.type)
    }

    // MARK: - Container view

    /// Wraps MKMapView to apply deferred zoom in layoutSubviews,
    /// which is guaranteed to fire when the frame becomes valid
    /// (unlike delegate callbacks during NavigationStack transitions).
    final class MapContainerView: UIView {
        let mapView: MKMapView
        var targetRegion: MKCoordinateRegion?

        init(mapView: MKMapView) {
            self.mapView = mapView
            super.init(frame: .zero)
            addSubview(mapView)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            mapView.frame = bounds
            if let region = targetRegion, bounds.width > 0, bounds.height > 0 {
                targetRegion = nil
                DispatchQueue.main.async {
                    self.mapView.setRegion(region, animated: false)
                }
            }
        }
    }

    // MARK: - Annotations

    enum PinKind {
        case user, stop
    }

    final class PinAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let kind: PinKind

        init(coordinate: CLLocationCoordinate2D, kind: PinKind) {
            self.coordinate = coordinate
            self.kind = kind
        }
    }

    private static func routeKey(for coordinates: [CLLocationCoordinate2D]) -> String {
        guard !coordinates.isEmpty else { return "none" }
        return coordinates.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
    }

    private static func regionKey(
        userCoordinate: CLLocationCoordinate2D,
        stopCoordinate: CLLocationCoordinate2D,
        routeKey: String
    ) -> String {
        "\(userCoordinate.latitude),\(userCoordinate.longitude)|\(stopCoordinate.latitude),\(stopCoordinate.longitude)|\(routeKey)"
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var stopColor: Color
        var stopType: TransportType
        var stopName = ""
        var lineName = ""
        var stopAnnotationKey: String?
        var routeKey: String?
        var regionKey: String?

        init(stopColor: Color, stopType: TransportType) {
            self.stopColor = stopColor
            self.stopType = stopType
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }

            switch pin.kind {
            case .user:
                return makeUserDot(for: pin, in: mapView)
            case .stop:
                return makeStopPin(for: pin, in: mapView)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(stopColor)
                renderer.lineWidth = 4
                renderer.lineDashPattern = [8, 5]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        private func makeUserDot(for annotation: PinAnnotation, in mapView: MKMapView) -> MKAnnotationView {
            let id = "RouteUserDot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.isAccessibilityElement = true
            view.accessibilityLabel = annotation.kind == .stop ? "\(stopName), \(stopType.displayName) stop" : "Your location"

            let size: CGFloat = 24
            let container = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))

            let halo = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
            halo.layer.cornerRadius = size / 2
            container.addSubview(halo)

            let inner = UIView(frame: CGRect(x: 6, y: 6, width: 12, height: 12))
            inner.backgroundColor = .systemBlue
            inner.layer.cornerRadius = 6
            inner.layer.borderColor = UIColor.white.cgColor
            inner.layer.borderWidth = 2
            inner.layer.shadowColor = UIColor.black.cgColor
            inner.layer.shadowOpacity = 0.3
            inner.layer.shadowOffset = .zero
            inner.layer.shadowRadius = 2
            container.addSubview(inner)

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(container)
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.centerOffset = .zero
            return view
        }

        private func makeStopPin(for annotation: PinAnnotation, in mapView: MKMapView) -> MKAnnotationView {
            let id = "RouteStopPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.isAccessibilityElement = true
            view.accessibilityLabel = annotation.kind == .stop ? "\(stopName), \(stopType.displayName) stop" : "Your location"

            view.accessibilityLabel = "\(stopName), \(stopType.displayName) \(lineName)"
            let badge = MapLineBadge(name: lineName, type: stopType, color: stopColor)

            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(badge)
            view.frame = badge.bounds
            view.centerOffset = .zero
            return view
        }
    }
}

#if DEBUG
#Preview {
    RouteMapView(
        userCoordinate: PreviewData.userCoordinate.clLocationCoordinate2D,
        stop: PreviewData.stops[0],
        stopColor: StopPalette.colors[0],
        walkingRoute: PreviewData.walkingRoute
    )
    .frame(height: 400)
}
#endif
