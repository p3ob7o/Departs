import SwiftUI
import MapKit

struct RouteMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D
    let stop: NearbyStop
    let stopColor: Color
    let walkingRoute: WalkingRoute?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = true
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.stopColor = stopColor
        context.coordinator.stopType = stop.type

        // Remove old content
        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)

        // Add user dot
//        let userPin = PinAnnotation(
//            coordinate: userCoordinate,
//            kind: .user
//        )
//        map.addAnnotation(userPin)

        // Add stop pin
        let stopPin = PinAnnotation(
            coordinate: stop.location.clLocationCoordinate2D,
            kind: .stop
        )
        map.addAnnotation(stopPin)

        // Add walking route polyline
        if let route = walkingRoute {
            let coords = route.geometry.clCoordinates
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            map.addOverlay(polyline)
        }

        // Fit bounds to user + stop (and route if available)
        var points = [userCoordinate, stop.location.clLocationCoordinate2D]
        if let route = walkingRoute {
            points.append(contentsOf: route.geometry.clCoordinates)
        }
        let mapPoints = points.map { MKMapPoint($0) }
        var mapRect = mapPoints.dropFirst().reduce(MKMapRect(origin: mapPoints[0], size: MKMapSize(width: 0, height: 0))) { rect, point in
            rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        // Ensure a minimum visible area (~400m) so short walks aren't over-zoomed
        let minSize = MKMapPointsPerMeterAtLatitude(userCoordinate.latitude) * 400
        if mapRect.size.width < minSize { mapRect = mapRect.insetBy(dx: -(minSize - mapRect.size.width) / 2, dy: 0) }
        if mapRect.size.height < minSize { mapRect = mapRect.insetBy(dx: 0, dy: -(minSize - mapRect.size.height) / 2) }
        let inset = max(mapRect.size.width, mapRect.size.height) * 0.5
        mapRect = mapRect.insetBy(dx: -inset, dy: -inset)
        map.setVisibleMapRect(mapRect, animated: false)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(stopColor: stopColor, stopType: stop.type)
    }

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

    final class Coordinator: NSObject, MKMapViewDelegate {
        var stopColor: Color
        var stopType: TransportType

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
                renderer.lineWidth = 3
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        private func makeUserDot(for annotation: PinAnnotation, in mapView: MKMapView) -> MKAnnotationView {
            let id = "RouteUserDot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation

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

            let size: CGFloat = 32
            let circle = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            circle.backgroundColor = UIColor(stopColor)
            circle.layer.cornerRadius = size / 2
            circle.layer.shadowColor = UIColor.black.cgColor
            circle.layer.shadowOpacity = 0.3
            circle.layer.shadowOffset = CGSize(width: 0, height: 2)
            circle.layer.shadowRadius = 3

            let label = UILabel(frame: circle.bounds)
            label.text = stopType.label
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 14, weight: .bold)
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
