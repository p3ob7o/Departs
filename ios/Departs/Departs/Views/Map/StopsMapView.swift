import SwiftUI
import MapKit

struct StopsMapView: UIViewRepresentable {
    /// Where the map stands when MapKit's own location may not move it: the
    /// app's usable fix, else the centre of the saved area. Nil: no centre, no ring.
    let fallbackCenter: CLLocationCoordinate2D?
    /// True while the app holds a usable fix. Only then may MapKit's live,
    /// precise location move the map, so a coarse position never does.
    var followsLiveLocation = false
    let groups: [TransitStore.StopGroup]
    var selectedStopID: String? = nil
    var onSelect: (String?) -> Void = { _ in }

    /// The 400 m ring around the point the map is centred on. The framing
    /// below never depends on it, so hiding it is this one line.
    static let showsRing = true
    /// The square always spans this many metres, centred on the rider: the
    /// 400 m ring and its margin. The ring's radius is the width ÷ 2.4.
    static let span = Double(TransitStore.radius) * 2.4
    /// MapKit's location moves the map only when it is at least this accurate.
    static let liveAccuracy: CLLocationAccuracy = 100

    func makeUIView(context: Context) -> HomeMapView {
        let map = HomeMapView()
        // Nothing can bring a panned map back, and it stays on the rider.
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = true
        map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        map.delegate = context.coordinator
        map.onResize = { [weak coordinator = context.coordinator, weak map] in
            guard let coordinator, let map else { return }
            coordinator.frame(map, reset: true)
        }
        return map
    }

    func updateUIView(_ map: HomeMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.restoringSelection = true
        defer { context.coordinator.restoringSelection = false }
        context.coordinator.fallback = fallbackCenter
        context.coordinator.followsLive = followsLiveLocation
        context.coordinator.frame(map)

        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        for pin in map.annotations.compactMap({ $0 as? StopAnnotation }) {
            guard let group = groupsByID[pin.stopId], group.stops == pin.stops, group.lines == pin.lines else {
                map.removeAnnotation(pin)
                continue
            }
        }
        let existingIDs = Set(map.annotations.compactMap { ($0 as? StopAnnotation)?.stopId })
        map.addAnnotations(groups.filter { !existingIDs.contains($0.id) }.map(StopAnnotation.init))
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
        let lines: [LineInfo]
        let spokenLabel: String

        init(group: TransitStore.StopGroup) {
            coordinate = group.coordinate.clLocationCoordinate2D
            stopId = group.id
            stops = group.stops
            lines = group.lines
            let services = lines.map { String(localized: "\($0.type.displayName) \($0.shortName)") }.formatted(.list(type: .and))
            spokenLabel = String(localized: "\(group.name), \(services)")
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (String?) -> Void = { _ in }
        var restoringSelection = false
        var fallback: CLLocationCoordinate2D?
        var followsLive = false
        /// MapKit's latest location, kept only while it is precise.
        private var live: CLLocationCoordinate2D?
        private var centre: CLLocationCoordinate2D?
        private var ring: MKCircle?

        /// What the map centres on, in order: MapKit's precise live location
        /// while the app holds a usable fix, else the fallback, else nothing.
        var target: CLLocationCoordinate2D? { (followsLive ? live : nil) ?? fallback }

        func frame(_ map: MKMapView, reset: Bool = false) {
            guard let target else {
                // Location is off: no circle may claim an area is searched.
                if centre != nil { centre = nil; drawRing(nil, on: map) }
                return
            }
            if let centre, !reset {
                guard CLLocation(target).distance(from: CLLocation(centre)) > 0.5 else { return }
                map.setCenter(target, animated: true)
            } else if map.bounds.width > 0 {
                map.setRegion(MKCoordinateRegion(center: target, latitudinalMeters: StopsMapView.span,
                                                 longitudinalMeters: StopsMapView.span), animated: false)
            }
            if centre.map({ CLLocation($0).distance(from: CLLocation(target)) }) != 0 { drawRing(target, on: map) }
            centre = target
        }

        private func drawRing(_ centre: CLLocationCoordinate2D?, on map: MKMapView) {
            if let ring { map.removeOverlay(ring) }
            ring = nil
            guard StopsMapView.showsRing, let centre else { return }
            let circle = MKCircle(center: centre, radius: Double(TransitStore.radius))
            map.addOverlay(circle)
            ring = circle
        }

        /// Keeps MapKit's location only while it is precise. Precise Location
        /// off gives a fix kilometres wide: it never moves the map.
        func receiveLive(_ location: CLLocation?) {
            if let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= StopsMapView.liveAccuracy {
                live = location.coordinate
            } else { live = nil }
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            receiveLive(userLocation.location)
            frame(mapView)
        }

        func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: any Error) {
            receiveLive(nil)
            frame(mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? StopAnnotation else { return nil }
            let id = "StopPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MapLineAnnotationView
                ?? MapLineAnnotationView(annotation: pin, reuseIdentifier: id)
            view.annotation = pin
            view.configure(lines: pin.lines)
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
    private var badges: [MapLineBadge] = []
    private var moreLabel: UILabel?

    func configure(name: String, type: TransportType, color: Color) {
        arrange([MapLineBadge(name: name, type: type, color: color)], extra: 0)
    }

    func configure(lines: [LineInfo]) {
        arrange(lines.prefix(3).map { MapLineBadge(name: $0.shortName, type: $0.type, color: StopPalette.modeColor($0.type)) },
                extra: max(0, lines.count - 3))
    }

    private func arrange(_ newBadges: [MapLineBadge], extra: Int) {
        badges.forEach { $0.removeFromSuperview() }
        moreLabel?.removeFromSuperview()
        moreLabel = nil
        badges = newBadges
        var drawings: [UIView] = newBadges
        if extra > 0 {
            let label = UILabel()
            label.text = "+\(extra.formatted())"
            label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold), maximumPointSize: 18)
            label.textColor = .label
            label.backgroundColor = .systemBackground
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            label.textAlignment = .center
            label.sizeToFit()
            label.frame.size = CGSize(width: label.bounds.width + 8, height: max(28, label.bounds.height + 8))
            moreLabel = label
            drawings.append(label)
        }
        let width = drawings.reduce(0) { $0 + $1.bounds.width } + CGFloat(max(0, drawings.count - 1)) * 3
        frame.size = CGSize(width: max(44, width + 8), height: max(44, (drawings.map { $0.bounds.height }.max() ?? 28) + 8))
        var x = (bounds.width - width) / 2
        for drawing in drawings {
            drawing.frame.origin = CGPoint(x: x, y: (bounds.height - drawing.bounds.height) / 2)
            x += drawing.bounds.width + 3
            addSubview(drawing)
        }
        centerOffset = .zero
        collisionMode = .rectangle
        displayPriority = .required
        isAccessibilityElement = true
        updateSelection()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateSelection()
    }

    private func updateSelection() {
        badges.forEach { $0.setSelected(isSelected) }
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
        // The list below the map uses the full Dynamic Type size.
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold), maximumPointSize: 18)
        label.textColor = .white
        label.sizeToFit()
        let symbolSize: CGFloat = 13
        let width = label.bounds.width + symbolSize + 19
        let height = max(28, label.bounds.height + 8)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
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

/// Reports size changes, so the fixed span is applied once the square has its size.
final class HomeMapView: MKMapView {
    var onResize: (() -> Void)?
    private var lastSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onResize?()
    }
}

private extension CLLocation {
    convenience init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

#if DEBUG
#Preview {
    StopsMapView(
        fallbackCenter: PreviewData.userCoordinate.clLocationCoordinate2D,
        groups: PreviewData.stops.map { .init(id: $0.id, name: $0.name, stops: [$0]) }
    )
    .frame(height: 400)
}
#endif
