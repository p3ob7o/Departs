import SwiftUI
import MapKit

struct RouteMapView: UIViewRepresentable {
    /// Where the walk starts. Nil when location is off and no area is saved:
    /// the map then shows the stop alone.
    let userCoordinate: CLLocationCoordinate2D?
    let stop: NearbyStop
    let stopColor: Color
    let walkingRoute: WalkingRoute?
    var line: LineInfo? = nil
    var originIsCurrentLocation = true

    func makeUIView(context: Context) -> MapContainerView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.delegate = context.coordinator
        return MapContainerView(mapView: map)
    }

    func updateUIView(_ container: MapContainerView, context: Context) {
        let map = container.mapView
        context.coordinator.stopColor = stopColor
        context.coordinator.stopType = line?.type ?? stop.type
        context.coordinator.stopName = stop.name
        context.coordinator.lineName = line?.shortName ?? stop.lines.first?.shortName ?? stop.type.label
        context.coordinator.originLabel = originIsCurrentLocation ? String(localized: "Walking start") : String(localized: "Last location")
        let coordinates = MapCoordinates(platform: stop.location.clLocationCoordinate2D, origin: userCoordinate,
                                         route: walkingRoute?.geometry.clCoordinates ?? [])
        let stopAnnotationKey = "\(stop.id)|\(stop.location.lat)|\(stop.location.lon)|\(context.coordinator.lineName)"

        if context.coordinator.stopAnnotationKey != stopAnnotationKey {
            let existing = map.annotations.compactMap { $0 as? PinAnnotation }.filter { $0.kind == .stop }
            map.removeAnnotations(existing)

            if let platform = coordinates.platform {
                map.addAnnotation(PinAnnotation(coordinate: platform, kind: .stop))
            }
            context.coordinator.stopAnnotationKey = stopAnnotationKey
        }

        let originKey = coordinates.origin.map { "\($0.latitude)|\($0.longitude)|\(originIsCurrentLocation)" } ?? "none"
        if context.coordinator.originKey != originKey {
            map.removeAnnotations(map.annotations.compactMap { $0 as? PinAnnotation }.filter { $0.kind == .user })
            if let origin = coordinates.origin {
                map.addAnnotation(PinAnnotation(coordinate: origin, kind: .user))
            }
            map.showsUserLocation = coordinates.origin != nil
            context.coordinator.originKey = originKey
        }

        let routeCoordinates = coordinates.route
        let routeKey = Self.routeKey(for: routeCoordinates)
        if context.coordinator.routeKey != routeKey {
            map.removeOverlays(map.overlays)
            if routeCoordinates.count > 1 {
                let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
                map.addOverlay(polyline)
            }
            context.coordinator.routeKey = routeKey
        }

        let regionKey = "\(originKey)|\(stop.location.lat),\(stop.location.lon)|\(routeKey)"
        if context.coordinator.regionKey != regionKey {
            context.coordinator.regionKey = regionKey
            let region = coordinates.fittedRegion
            container.fittedRegion = region
            container.targetRegion = region
            if let region, map.bounds.width > 0, map.bounds.height > 0 {
                container.targetRegion = nil
                map.setRegion(region, animated: false)
            }
        }
    }

    struct MapCoordinates {
        let platform: CLLocationCoordinate2D?
        let origin: CLLocationCoordinate2D?
        let route: [CLLocationCoordinate2D]

        init(platform: CLLocationCoordinate2D, origin: CLLocationCoordinate2D?, route: [CLLocationCoordinate2D]) {
            func isValid(_ point: CLLocationCoordinate2D) -> Bool {
                Coordinate(lat: point.latitude, lon: point.longitude).isValid
            }
            let validPlatform = isValid(platform) ? platform : nil
            self.platform = validPlatform
            self.origin = origin.flatMap { start in
                guard isValid(start) else { return nil }
                if let validPlatform {
                    let stop = Coordinate(lat: validPlatform.latitude, lon: validPlatform.longitude)
                    let rider = Coordinate(lat: start.latitude, lon: start.longitude)
                    // For a distant pin, show the platform at the usual stop scale.
                    guard rider.distance(to: stop) < TransitStore.maximumWalkingDistance else { return nil }
                }
                return start
            }
            self.route = validPlatform != nil && self.origin != nil && route.allSatisfy(isValid)
                ? route : []
        }

        var fittedRegion: MKCoordinateRegion? {
            let points = [platform, origin].compactMap { $0 } + route
            guard let first = points.first else { return nil }
            var south = first.latitude, north = first.latitude
            for point in points.dropFirst() {
                south = min(south, point.latitude)
                north = max(north, point.latitude)
            }

            // Take the complement of the largest gap on the longitude circle.
            let longitudes = points.map(\.longitude).sorted()
            var west = longitudes[0]
            var largestGap = west + 360 - longitudes[longitudes.count - 1]
            for (left, right) in zip(longitudes, longitudes.dropFirst()) where right - left > largestGap {
                largestGap = right - left
                west = right
            }
            let width = 360 - largestGap
            let midpoint = west + width / 2

            // Keep 60% padding and the usual minimum span. Move the latitude
            // centre inward near a pole so the padded edges remain valid.
            let height = min(max((north - south) * 1.6, 0.00135), 180)
            let latitudeLimit = 90 - height / 2
            let center = CLLocationCoordinate2D(latitude: min(max((south + north) / 2, -latitudeLimit), latitudeLimit),
                                                 longitude: midpoint > 180 ? midpoint - 360 : midpoint)
            let span = MKCoordinateSpan(latitudeDelta: height, longitudeDelta: min(max(width * 1.6, 0.002), 360))
            return MKCoordinateRegion(center: center, span: span)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(stopColor: stopColor, stopType: stop.type)
    }

    // MARK: - Container view

    /// Wraps MKMapView to apply deferred framing in layoutSubviews,
    /// which is guaranteed to fire when the frame becomes valid
    /// (unlike delegate callbacks during NavigationStack transitions).
    final class MapContainerView: UIView {
        let mapView: MKMapView
        var fittedRegion: MKCoordinateRegion?
        var targetRegion: MKCoordinateRegion?

        init(mapView: MKMapView) {
            self.mapView = mapView
            super.init(frame: .zero)
            addSubview(mapView)
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Under the status bar the map is shown and takes no touch, as on home (A26).
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            point.y < safeAreaInsets.top ? nil : super.hitTest(point, with: event)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if mapView.bounds.size != bounds.size {
                targetRegion = fittedRegion
            }
            mapView.frame = bounds
            if targetRegion != nil, bounds.width > 0, bounds.height > 0 {
                targetRegion = nil
                DispatchQueue.main.async {
                    guard let region = self.fittedRegion else { return }
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

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var stopColor: Color
        var stopType: TransportType
        var stopName = ""
        var lineName = ""
        var originLabel = ""
        var originKey: String?
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
            view.accessibilityLabel = originLabel
            view.accessibilityIdentifier = "route-origin"

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
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MapLineAnnotationView
                ?? MapLineAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.configure(name: lineName, type: stopType, color: stopColor)
            view.accessibilityLabel = String(localized: "\(stopName), \(stopType.displayName) \(lineName)")
            view.accessibilityIdentifier = "route-platform"
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
