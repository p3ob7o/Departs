import MapKit
import SwiftUI

struct DepartureDetailView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.dismiss) private var dismiss
    let selection: StopLineSelection
    @Bindable var store: TransitStore
    @State private var countdownStart = Date.now
    /// The widest countdown among the departures shown, so each sits
    /// right-aligned in one column: the 4 of "4 min" above the 0 of "10 min".
    @State private var countdownColumn: CGFloat?

    private var title: String { "\(selection.line.shortName) \(selection.line.direction)" }

    var body: some View {
        GeometryReader { geometry in
            let accessibility = textSize.isAccessibilitySize
            // At standard sizes the bar is hidden and the map has home's frame:
            // the square, plus the strip under a tall status bar (O22, A27).
            let strip = MapStrip.height(statusBar: geometry.safeAreaInsets.top, accessibilitySize: accessibility)
            TimelineView(.periodic(from: countdownStart, by: 15)) { timeline in
                let date = max(timeline.date, Date.now)
                let board = store.boards[selection.id]
                let fresh = store.isBoardFresh(for: selection, at: date)
                let walk = store.walk(for: selection.stop, at: date)
                let shown = board.map { Array($0.upcoming(at: $0.checkedAt).prefix(4)) } ?? []
                VStack(spacing: 0) {
                    if !accessibility {
                        map(width: geometry.size.width, strip: strip, walk: walk, at: date)
                        controls(walk: walk, at: date)
                    }
                    List {
                        if accessibility {
                            // As before: the map scrolls away and the bar keeps
                            // back, walk and pin within reach (A39).
                            map(width: geometry.size.width, walk: walk, at: date)
                                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                            heading(walk: walk, at: date)
                                .listRowSeparator(.hidden)
                                .listRowInsets(.vertical, 8)
                        }
                        if let board {
                            if !fresh { refreshButton(savedAt: board.checkedAt) }
                            if !board.hasDepartureWithinHorizon {
                                Text("Nothing in the next hour").accessibilityIdentifier("line-empty")
                            }
                            ForEach(shown) { departure in
                                departureRow(departure, fresh: fresh, at: date)
                                    .listRowInsets(.vertical, 0)
                            }
                        } else if store.boardErrors.contains(selection.id) {
                            refreshButton(savedAt: nil)
                        } else {
                            Label("Checking departures…", systemImage: "clock")
                                .accessibilityIdentifier("board-status")
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 0)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .background(alignment: .topLeading) {
                        if !accessibility {
                            CountdownColumn.Reader(texts: CountdownColumn.texts(shown, fresh: fresh, now: date)) { countdownColumn = $0 }
                        }
                    }
                    .accessibilityIdentifier("departure-detail")
                    .refreshable { await store.refreshSelection(selection, force: true) }
                }
                .ignoresSafeArea(.container, edges: strip > 0 ? .top : [])
            }
        }
        // Kept for VoiceOver and the back stack, also while the bar is hidden.
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(textSize.isAccessibilitySize ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if textSize.isAccessibilitySize {
                    WalkingDirectionsButton(selection: selection) {
                        SwiftUI.Label("Walking directions", systemImage: "figure.walk")
                    }
                    Button(pinLabel, systemImage: pinSymbol) { store.togglePin(selection) }
                        .accessibilityIdentifier(pinID)
                }
            }
        }
        .task(id: selection.id) { await store.refreshSelection(selection) }
        .background { EdgeSwipeBack().frame(width: 0, height: 0) }
        #if DEBUG
        .overlay(alignment: .bottomLeading) { OpenedMapAppsMarker() }
        #endif
    }

    private var pinLabel: String {
        store.isPinned(selection) ? String(localized: "Unpin this direction") : String(localized: "Pin this direction")
    }
    private var pinSymbol: String { store.isPinned(selection) ? "pin.fill" : "pin" }
    private var pinID: String { store.isPinned(selection) ? "unpin-route" : "pin-route" }

    /// `strip` points of the map lie under the status bar, above its square.
    /// MapKit keeps the route inside the safe area, so inside the square.
    private func map(width: CGFloat, strip: CGFloat = 0, walk: CachedWalk?, at date: Date) -> some View {
        RouteMapView(userCoordinate: store.walkingOrigin?.clLocationCoordinate2D,
                     stop: selection.stop, stopColor: StopPalette.modeColor(selection.line.type),
                     walkingRoute: walk?.route, line: selection.line,
                     originIsCurrentLocation: store.location?.isUsable(at: date) == true)
            .frame(width: width, height: width + strip)
            .accessibilityIdentifier("line-map")
    }

    /// Under the map, fixed above the list: back, the line and its direction
    /// with the stop below them, then walk and pin (O22). Plain symbols in the
    /// label colour with 44 pt targets, aligned with the title's first line.
    private func controls(walk: CachedWalk?, at date: Date) -> some View {
        // The title shares its line with the buttons and wraps beside them. The
        // stop line below runs under walk and pin to the list's 16 pt margin
        // (A38). Both layers meet at the title's first baseline.
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            VStack(alignment: .leading, spacing: 4) {
                titleText.padding(.trailing, Self.buttonWidth * 2 + 4)
                stopLineText(walk: walk, at: date).padding(.trailing, 16 - Self.edge)
            }
            .padding(.leading, Self.buttonWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.primary)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button { dismiss() } label: { ControlSymbol(name: "chevron.backward") }
                    .accessibilityLabel(Text("Back"))
                    .accessibilityIdentifier("line-back")
                    .accessibilitySortPriority(3)
                Spacer(minLength: 0)
                WalkingDirectionsButton(selection: selection) { ControlSymbol(name: "figure.walk") }
                Button { store.togglePin(selection) } label: { ControlSymbol(name: pinSymbol) }
                    .accessibilityLabel(Text(pinLabel))
                    .accessibilityIdentifier(pinID)
            }
        }
        // VoiceOver reads back, the line, the stop, then walk and pin.
        .accessibilityElement(children: .contain)
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, Self.edge)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// The controls sit this close to the screen's edges; each takes this width.
    private static let edge: CGFloat = 4
    private static let buttonWidth: CGFloat = 44

    /// The full service, wrapped and never truncated. At standard sizes this is
    /// the only place the line is named on screen.
    private var titleText: some View {
        Text(title).font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail-direction")
            .accessibilitySortPriority(2)
    }

    private func stopLineText(walk: CachedWalk?, at date: Date) -> some View {
        Text(stopSummary(walk: walk, at: date)).font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("detail-stop-name")
            .accessibilitySortPriority(1)
    }

    /// At accessibility sizes the line and the stop form a row of the list.
    private func heading(walk: CachedWalk?, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            titleText
            stopLineText(walk: walk, at: date)
        }.foregroundStyle(Color.primary)
    }

    private func stopSummary(walk: CachedWalk?, at date: Date) -> String {
        let current = store.location?.isUsable(at: date) == true
        if let walk {
            return StopLine.walk(stop: selection.stop.name, walk: TransitFormat.walk(walk.route, fromCurrentLocation: current),
                                 distance: TransitFormat.distance(walk.route.distance))
        }
        // No origin at all: a pinned route opened while location is off.
        return current || store.walkingOrigin == nil ? selection.stop.name : StopLine.fromThisArea(stop: selection.stop.name)
    }

    private func refreshButton(savedAt: Date?) -> some View {
        Button { Task { await store.refreshSelection(selection, force: true) } } label: {
            if let savedAt {
                Label("Saved times from \(savedAt.formatted(date: .omitted, time: .shortened)) · Refresh", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            } else {
                Label("Couldn't load · Retry", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }
        }.foregroundStyle(.tint).accessibilityIdentifier("refresh-line")
    }

    private func departureRow(_ departure: Departure, fresh: Bool, at date: Date) -> some View {
        let content = LineDepartureContent(departure: departure, fresh: fresh, now: date)
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        // A countdown sits right-aligned in the shared column. A clock alone,
        // for saved times or beyond the hour, keeps its place on the left.
        let column = content.countdown != nil && !textSize.isAccessibilitySize ? countdownColumn : nil
        return layout {
            Text(content.countdown ?? content.clock).font(CountdownColumn.font).monospacedDigit()
                .modifier(CountdownTransition(value: content.countdown ?? content.clock))
                .frame(minWidth: column, alignment: .trailing)
                // A row's divider starts at its first text. Inside the column
                // that text moves right, so the divider starts at the column.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
            if content.live {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right").accessibilityHidden(true)
                    if let delay = content.delay { Text(delay) }
                }.font(.subheadline)
            }
            if content.countdown != nil { Text(content.clock).font(.subheadline).monospacedDigit() }
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spoken)
        .accessibilityIdentifier("line-departure")
    }
}

struct LineDepartureContent {
    /// "12 min" or "Now"; nil for saved times and beyond the hour.
    var countdown: String? { time?.text }
    let clock: String
    let live: Bool
    let delay: String?
    private let time: Countdown?
    /// VoiceOver keeps the full phrase: "In 12 min. 00:00".
    var spoken: String {
        var parts = time.map { [$0.spoken, clock] } ?? [clock]
        if live { parts.append(String(localized: "Live departure")) }
        if let delay { parts.append(delay) }
        return parts.joined(separator: ". ")
    }

    init(departure: Departure, fresh: Bool, now: Date) {
        time = fresh ? TimeFormatter.countdown(departure.time, now: now) : nil
        clock = TimeFormatter.formatTime(departure.time)
        live = fresh && departure.realTime
        let delayMinutes = Int(max(0, departure.delay ?? 0) / 60)
        delay = live && delayMinutes >= 1 ? String(localized: "\(TransitFormat.minutes(delayMinutes)) late") : nil
    }
}

/// UIKit stops the swipe from the left edge on a screen that hides its bar,
/// and the line screen hides it at standard sizes (O22). While the line screen
/// is shown this becomes the swipe's delegate, through public API only, and
/// lets it begin again; afterwards the gesture gets its own delegate back, so
/// the root screen never starts a pop it cannot finish.
struct EdgeSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        private weak var gesture: UIGestureRecognizer?
        private weak var original: (any UIGestureRecognizerDelegate)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let pop = navigationController?.interactivePopGestureRecognizer, pop.delegate !== self else { return }
            original = pop.delegate
            gesture = pop
            pop.delegate = self
            pop.isEnabled = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if let gesture, gesture.delegate === self { gesture.delegate = original }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        /// Every other gesture on the screen waits for the swipe to fail, so a
        /// swipe that starts at the edge goes back over the map too, instead of
        /// panning it. The swipe gives up when a touch starts away from the edge
        /// or moves along it, so taps, long presses, scrolls and other pans still
        /// work (`testEdgeSwipeLeavesTapsLongPressesAndScrollsAlone`).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// The stop under the line and its direction. A no-break space keeps each "·"
/// with the word before it, so a wrapped stop line never starts with one.
enum StopLine {
    static func walk(stop: String, walk: String, distance: String) -> String {
        String(localized: "\(stop)\u{00A0}· \(walk)\u{00A0}· \(distance)")
    }

    static func fromThisArea(stop: String) -> String {
        String(localized: "\(stop)\u{00A0}· from this area")
    }
}

/// A control under the line map: a plain symbol in a 44 pt target.
struct ControlSymbol: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.title3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// The line screen's countdowns share one column, right-aligned in it. Its
/// width comes from the departures shown, not from the rows the list has
/// rendered, as for the badges on home (`BadgeColumn`).
enum CountdownColumn {
    static let font = Font.headline

    /// The countdowns the rows show: "4 min", "10 min", "Now". Saved times and
    /// departures beyond the hour show a clock instead and take no part.
    static func texts(_ departures: [Departure], fresh: Bool, now: Date) -> [String] {
        departures.compactMap { LineDepartureContent(departure: $0, fresh: fresh, now: now).countdown }
    }

    /// Every countdown laid on top of each other: the stack is as wide as the widest.
    struct Stack: View {
        let texts: [String]
        var body: some View {
            ZStack(alignment: .trailing) {
                ForEach(Array(Set(texts)).sorted(), id: \.self) { Text($0).font(CountdownColumn.font).monospacedDigit().fixedSize() }
            }
        }
    }

    /// Measures the stack without drawing it and reports its width.
    struct Reader: View {
        let texts: [String]
        let onWidth: (CGFloat?) -> Void
        var body: some View {
            Stack(texts: texts)
                .fixedSize()
                .hidden()
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0 > 0 ? $0 : nil) }
        }
    }
}

/// The app that opens walking directions to the stop (O21).
enum MapApp: String, Codable, CaseIterable, Identifiable {
    case apple, google
    var id: String { rawValue }
    /// Product names: shown as they are, never translated.
    var name: String { self == .apple ? "Apple Maps" : "Google Maps" }
}

/// What the walk button does. Google Maps is offered only when it is
/// installed; without it the button opens Apple Maps, as before, and offers
/// no choice. A choice is remembered until a long press changes it. A
/// remembered Google Maps that has since been removed is forgotten.
struct MapAppChoice {
    enum Tap: Equatable {
        case open(MapApp)
        case showChoice
    }

    static let googleScheme = URL(string: "comgooglemaps://")!

    let persistence: TransitPersistence
    let canOpen: (URL) -> Bool

    var offersChoice: Bool { canOpen(Self.googleScheme) }

    /// The app a tap opens without asking, if one was chosen and is still there.
    func remembered() -> MapApp? {
        guard let app = persistence.loadMapApp() else { return nil }
        if app == .google, !offersChoice {
            persistence.clearMapApp()
            return nil
        }
        return app
    }

    func tap() -> Tap {
        let app = remembered() // first, so a removed Google Maps is forgotten
        guard offersChoice else { return .open(.apple) }
        return app.map(Tap.open) ?? .showChoice
    }

    func choose(_ app: MapApp) { persistence.saveMapApp(app) }

    /// Walking directions to the stop's coordinate.
    static func googleURL(for stop: NearbyStop) -> URL {
        URL(string: String(format: "comgooglemaps://?daddr=%.6f,%.6f&directionsmode=walking", stop.location.lat, stop.location.lon))!
    }

    @MainActor static var live: MapAppChoice {
        MapAppChoice(persistence: TransitPersistence()) { url in
            #if DEBUG
            // The simulator has no Google Maps. UI tests stand one in.
            if url.scheme == googleScheme.scheme, testsGoogleMaps { return true }
            #endif
            return UIApplication.shared.canOpenURL(url)
        }
    }

    #if DEBUG
    static var testsGoogleMaps: Bool { ProcessInfo.processInfo.environment["DEPARTS_TEST_GOOGLE_MAPS"] == "1" }
    #endif
}

/// The walk button: a plain button while only Apple Maps is there, a menu
/// before the first choice, and once chosen a tap that opens the remembered
/// app with the choice one long press away.
struct WalkingDirectionsButton<Label: View>: View {
    let selection: StopLineSelection
    @ViewBuilder let label: () -> Label
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var offersChoice = false
    @State private var remembered: MapApp?

    var body: some View {
        Group {
            if !offersChoice {
                Button { open(.apple) } label: { label() }
            } else if let remembered {
                Menu { choices } label: { label() } primaryAction: { open(remembered) }
            } else {
                Menu { choices } label: { label() }
            }
        }
        // Apple Maps first, also when the menu opens upwards.
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Walking directions"))
        .accessibilityIdentifier("walking-directions")
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    @ViewBuilder private var choices: some View {
        ForEach(MapApp.allCases) { app in
            Button {
                MapAppChoice.live.choose(app)
                remembered = app
                open(app)
            } label: {
                if app == remembered {
                    SwiftUI.Label { Text(verbatim: app.name) } icon: { Image(systemName: "checkmark") }
                } else {
                    Text(verbatim: app.name)
                }
            }
            .accessibilityIdentifier("map-app-\(app.rawValue)")
        }
    }

    private func refresh() {
        let choice = MapAppChoice.live
        offersChoice = choice.offersChoice
        remembered = choice.remembered()
    }

    private func open(_ app: MapApp) {
        #if DEBUG
        if MapAppChoice.testsGoogleMaps { OpenedMapApps.shared.opened.append(app); return }
        #endif
        switch app {
        case .apple:
            WalkingDirections.destination(for: selection).openInMaps(
                launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        case .google:
            openURL(MapAppChoice.googleURL(for: selection.stop))
        }
    }
}

#if DEBUG
/// What a UI test reads instead of watching another app open. Debug only.
@MainActor @Observable final class OpenedMapApps {
    static let shared = OpenedMapApps()
    var opened: [MapApp] = []
}

struct OpenedMapAppsMarker: View {
    var body: some View {
        if MapAppChoice.testsGoogleMaps {
            let opened = OpenedMapApps.shared.opened
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: opened.last.map { "\($0.name) \(opened.count)" } ?? "none"))
                .accessibilityIdentifier("opened-map-app")
        }
    }
}
#endif

enum WalkingDirections {
    static func destination(for selection: StopLineSelection) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: selection.stop.location.lat, longitude: selection.stop.location.lon), address: nil)
        item.name = selection.stop.name
        return item
    }
}
