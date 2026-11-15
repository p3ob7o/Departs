import SwiftUI
import MapKit

struct StopsMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D
    let groups: [TransitStore.StopGroup]
    var radius: Int = 400
    var selectedStopID: String? = nil
    var onSelect: (String?) -> Void = { _ in }

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
        context.coordinator.onSelect = onSelect
        let center = Coordinate(lat: userCoordinate.latitude, lon: userCoordinate.longitude)
        if context.coordinator.regionCenter != center || context.coordinator.radius != radius {
            map.setRegion(MKCoordinateRegion(center: userCoordinate,
                latitudinalMeters: Double(radius) * 2.4, longitudinalMeters: Double(radius) * 2.4), animated: false)
            context.coordinator.regionCenter = center
            context.coordinator.radius = radius
            map.removeOverlays(map.overlays)
            map.addOverlay(MKCircle(center: userCoordinate, radius: CLLocationDistance(radius)))
        }

        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        for pin in map.annotations.compactMap({ $0 as? StopAnnotation }) {
            guard let group = groupsByID[pin.stopId], group.stops == pin.stops else {
                map.removeAnnotation(pin)
                continue
            }
        }
        let existingIDs = Set(map.annotations.compactMap { ($0 as? StopAnnotation)?.stopId })
        map.addAnnotations(groups.filter { !existingIDs.contains($0.id) }.map(StopAnnotation.init))
        context.coordinator.restoringSelection = true
        defer { context.coordinator.restoringSelection = false }
        for pin in map.annotations.compactMap({ $0 as? StopAnnotation }) {
            let selected = map.selectedAnnotations.contains { ($0 as? StopAnnotation)?.stopId == pin.stopId }
            if pin.stopId == selectedStopID && !selected {
                map.selectAnnotation(pin, animated: false)
            } else if pin.stopId != selectedStopID && selected {
                map.deselectAnnotation(pin, animated: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class StopAnnotation: NSObject, MKAnnotation {
        let coordinate: CLLocationCoordinate2D
        let stopId: String
        let stops: [NearbyStop]
        let badgeName: String
        let spokenLabel: String
        let mode: TransportType

        init(group: TransitStore.StopGroup) {
            coordinate = group.coordinate.clLocationCoordinate2D
            stopId = group.id
            stops = group.stops
            let lines = group.lines
            mode = lines.first?.type ?? group.stops.first?.type ?? .tram
            let first = lines.first?.name ?? mode.displayName
            badgeName = lines.count > 1 ? "\(first) +\(lines.count - 1)" : first
            spokenLabel = "\(group.name), \(lines.map { "\($0.type.displayName) \($0.name)" }.joined(separator: ", "))"
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (String?) -> Void = { _ in }
        var regionCenter: Coordinate?
        var radius: Int?
        var restoringSelection = false

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? StopAnnotation else { return nil }
            let id = "StopPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MapLineAnnotationView
                ?? MapLineAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            view.configure(name: pin.badgeName, type: pin.mode, color: StopPalette.modeColor(pin.mode))
            view.accessibilityLabel = pin.spokenLabel
            view.accessibilityIdentifier = "stop-map-pin"
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if !restoringSelection, let pin = view.annotation as? StopAnnotation {
                onSelect(pin.stopId)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if !restoringSelection, view.annotation is StopAnnotation { onSelect(nil) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = .systemBlue
            renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08)
            renderer.lineWidth = 2
            return renderer
        }
    }
}

/// The drawing stays compact on the map; the annotation's transparent hit region
/// is at least 44 points. VoiceOver exposes the complete stop and service names.
final class MapLineAnnotationView: MKAnnotationView {
    private var badge: MapLineBadge?

    func configure(name: String, type: TransportType, color: Color) {
        badge?.removeFromSuperview()
        let badge = MapLineBadge(name: name, type: type, color: color)
        self.badge = badge
        frame.size = CGSize(width: max(48, badge.bounds.width + 8), height: max(48, badge.bounds.height + 8))
        badge.center = CGPoint(x: bounds.midX, y: bounds.midY)
        addSubview(badge)
        centerOffset = .zero
        collisionMode = .rectangle
        displayPriority = .defaultHigh
        isAccessibilityElement = true
        updateSelection()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateSelection()
    }

    private func updateSelection() {
        badge?.setSelected(isSelected)
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        zPriority = isSelected ? .max : .defaultUnselected
    }
}

/// Shared palette, line number and mode symbol for both MapKit wrappers.
final class MapLineBadge: UIView {
    private let selectionOutline = CAShapeLayer()

    init(name: String, type: TransportType, color: Color) {
        let label = UILabel()
        label.text = name
        // Map markers must retain their spatial meaning at large text sizes.
        // The selected-stop card below the map uses the full Dynamic Type size.
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold), maximumPointSize: 18)
        label.textColor = .white
        label.sizeToFit()
        let symbolSize: CGFloat = 13
        let width = label.bounds.width + symbolSize + 19
        let height = max(28, label.bounds.height + 8)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        backgroundColor = UIColor(color)
        layer.cornerRadius = 6
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 1.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 2
        let symbol = UIImageView(image: UIImage(systemName: type.symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize)))
        symbol.tintColor = .white
        symbol.contentMode = .scaleAspectFit
        symbol.frame = CGRect(x: 6, y: 4, width: symbolSize, height: height - 8)
        addSubview(symbol)
        label.frame = CGRect(x: symbolSize + 10, y: 4, width: label.bounds.width, height: height - 8)
        addSubview(label)
        selectionOutline.path = UIBezierPath(roundedRect: bounds.insetBy(dx: -3, dy: -3), cornerRadius: 9).cgPath
        selectionOutline.fillColor = UIColor.clear.cgColor
        selectionOutline.strokeColor = UIColor.systemBlue.cgColor
        selectionOutline.lineWidth = 3
        selectionOutline.isHidden = true
        layer.addSublayer(selectionOutline)
    }

    func setSelected(_ selected: Bool) {
        selectionOutline.isHidden = !selected
        layer.shadowOpacity = selected ? 0.5 : 0.25
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

#if DEBUG
#Preview {
    StopsMapView(
        userCoordinate: PreviewData.userCoordinate.clLocationCoordinate2D,
        groups: PreviewData.stops.map { .init(id: $0.id, name: $0.name, stops: [$0]) }
    )
    .frame(height: 400)
}
#endif
