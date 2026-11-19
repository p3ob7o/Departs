import SwiftUI

struct NearbyStopsView: View {
    typealias StopGroup = TransitStore.StopGroup
    @Bindable var store: TransitStore
    let locationState: LocationService.State
    let onSelect: (StopLineSelection) -> Void
    /// Asks for a new fix: "Try again" when no usable location arrived.
    let onLocate: () -> Void
    let onRefresh: () async -> Void
    var onDistantPins: () -> Void = {}
    var interactionID = "nearby"
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.openURL) private var openURL
    @State private var selectedMapStop: String?
    /// The directions offered at a map badge whose line runs more than one way.
    @State private var mapChoice: MapChoice?
    /// Where the choice points. Kept after it closes: an anchor that changed
    /// with the choice would move it while it is being dismissed.
    @State private var mapChoiceAnchor = CGRect.zero
    /// True from picking a direction until its choice has closed, so the stop
    /// keeps its ring as it does when a badge opens a line directly.
    @State private var pickedDirection = false
    @State private var countdownStart = Date.now
    /// The widest badge among every listed line, so destinations share one x.
    @State private var badgeColumn: CGFloat?

    /// A status bar at least this tall has a Dynamic Island or a notch. Only
    /// there does the map reach the top of the screen (O18): iOS blurs a map
    /// under the status bar by itself, and that strip is tall enough to keep
    /// the clock clear. On the 20 pt bar of an iPhone SE the blur is too short,
    /// and map labels would sit right behind the clock (A27).
    static let tallStatusBar: CGFloat = 44

    /// How far the home map reaches above its square, under the status bar.
    static func strip(statusBar: CGFloat, accessibilitySize: Bool) -> CGFloat {
        !accessibilitySize && statusBar >= tallStatusBar ? statusBar : 0
    }

    /// A choice of directions, offered at the badge that was tapped.
    struct MapChoice: Identifiable, Equatable {
        let id = UUID()
        let rows: [StopLineSelection]
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }

    /// The rows a touch on a stop's label stands for (O19). A badge is its
    /// line: every direction it runs from this stop. "+N" stands for the lines
    /// the label has no room for, and the whole label for all of them.
    static func rows(for part: StopsMapView.LabelPart, in group: StopGroup) -> [StopLineSelection] {
        let lines = group.lines.map(\.lineIdentity)
        let shown = lines.prefix(MapLineAnnotationView.shownLines)
        let rows: [StopLineSelection]
        switch part {
        case .line(let index) where shown.indices.contains(index):
            rows = group.active.filter { $0.line.lineIdentity == shown[index] }
        case .more:
            rows = group.active.filter { !shown.contains($0.line.lineIdentity) }
        default:
            rows = group.active
        }
        return rows.isEmpty ? group.active : rows
    }

    /// One direction opens its line. Several are offered at the badge.
    private func tappedLabel(_ stopID: String, _ part: StopsMapView.LabelPart, at frame: CGRect) {
        guard let group = store.mapGroups.first(where: { $0.id == stopID }) else { return }
        selectedMapStop = stopID
        let rows = Self.rows(for: part, in: group)
        if rows.count == 1 {
            mapChoice = nil
            onSelect(rows[0])
        } else if !rows.isEmpty {
            mapChoiceAnchor = frame
            mapChoice = MapChoice(rows: rows)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let strip = Self.strip(statusBar: geometry.safeAreaInsets.top, accessibilitySize: textSize.isAccessibilitySize)
            ScrollViewReader { proxy in
                TimelineView(.periodic(from: countdownStart, by: 15)) { timeline in
                    let date = max(timeline.date, Date.now)
                    VStack(spacing: 0) {
                        // Home has no bar. The square sits under the status bar,
                        // and on a tall status bar the map continues above it.
                        if !textSize.isAccessibilitySize {
                            map(width: geometry.size.width, strip: strip, at: date)
                        }
                        list(width: geometry.size.width, at: date)
                    }
                    .ignoresSafeArea(.container, edges: strip > 0 ? .top : [])
                }
                .onChange(of: store.areaRevision) { _, _ in
                    selectedMapStop = nil
                    mapChoice = nil
                    proxy.scrollTo("home-top", anchor: .top)
                }
                .onChange(of: mapChoice) { _, choice in
                    guard choice == nil else { return }
                    // Closed without a direction: nothing is selected.
                    if !pickedDirection { selectedMapStop = nil }
                    pickedDirection = false
                }
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private func list(width: CGFloat, at date: Date) -> some View {
        List {
            if textSize.isAccessibilitySize {
                map(width: width, at: date)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).id("home-top")
            } else {
                Color.clear.frame(height: 1).listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden).accessibilityHidden(true).id("home-top")
            }
            states(at: date)
            pinnedSections(at: date)
            ForEach(store.groups) { stopSections($0, at: date) }
        }
        .listStyle(.plain)
        .id(store.areaRevision)
        .environment(\.defaultMinListRowHeight, 0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .listSectionSpacing(0)
        .contentMargins(.top, 0, for: .scrollContent)
        // iOS 26 fades whatever passes the list's top edge, a pinned stop name
        // included. Below the map nothing needs it, and the name keeps its colour.
        // At accessibility sizes the list reaches the status bar, which needs it.
        .scrollEdgeEffectHidden(!textSize.isAccessibilitySize, for: .top)
        .background(alignment: .topLeading) {
            if !textSize.isAccessibilitySize {
                BadgeColumn.Reader(lines: BadgeColumn.lines(in: store.displayedOptions)) { badgeColumn = $0 }
            }
        }
        .accessibilityIdentifier("nearby-list")
        .onScrollPhaseChange { _, phase in store.setInteracting(phase != .idle, presentationID: interactionID) }
        .onDisappear { store.clearPresentation(interactionID) }
        .refreshable { await onRefresh() }
    }

    /// A stop's name stays at the top while its lines pass under it and leaves
    /// together with its last line. The last line therefore sits in a second,
    /// headerless section: the system pushes a pinned header out when its
    /// section ends. A stop with one line has an empty first section and never pins.
    @ViewBuilder private func stopSections(_ group: StopGroup, at date: Date) -> some View {
        let leading = group.hasMissingBoard ? group.active : Array(group.active.dropLast())
        Section {
            ForEach(leading) { row($0, at: date).listRowSeparator(.visible, edges: .bottom) }
        } header: { header(group, at: date) }
        Section {
            if group.hasMissingBoard {
                // The recovery row counts as the stop's last line.
                Button { Task { await onRefresh() } } label: {
                    Label("Couldn't load this stop · Retry", systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }.foregroundStyle(.tint).accessibilityIdentifier("retry-stop")
            } else if let last = group.active.last {
                row(last, at: date)
            }
        }
    }

    /// The same rule for pins: "Pinned elsewhere", when present, is the last line.
    @ViewBuilder private func pinnedSections(at date: Date) -> some View {
        let pins = store.nearbyPins
        let elsewhere = !store.distantPins.isEmpty
        if !pins.isEmpty || elsewhere {
            let leading = elsewhere ? pins : Array(pins.dropLast())
            Section {
                ForEach(leading) { row($0, at: date, showStop: true).listRowSeparator(.visible, edges: .bottom) }
            } header: { Text("Pinned").foregroundStyle(Color.primary).textCase(nil).modifier(StopHeader()) }
            .id("pinned")
            Section {
                if elsewhere {
                    Button(action: onDistantPins) {
                        Label("Pinned elsewhere (\(store.distantPins.count))", systemImage: "pin")
                            .frame(minHeight: 44)
                    }.foregroundStyle(.tint)
                } else if let last = pins.last {
                    row(last, at: date, showStop: true)
                }
            }
        }
    }

    private func header(_ group: StopGroup, at date: Date) -> some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
        return layout {
            Text(group.name).fontWeight(.semibold).foregroundStyle(Color.primary)
            if let walk = store.walk(for: group, at: date) {
                Text(TransitFormat.walk(walk.route, fromCurrentLocation: store.location?.isUsable(at: date) == true))
                    .foregroundStyle(StopPalette.secondaryText)
            }
        }
        .font(.subheadline).textCase(nil)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("stop-section")
        .modifier(StopHeader())
        .id(group.id)
    }

    /// The square, plus `strip` points above it when the map reaches the top of
    /// the screen. MapKit keeps its centre and span inside the safe area, so the
    /// square shows what it showed without the strip.
    private func map(width: CGFloat, strip: CGFloat = 0, at date: Date) -> some View {
        let usable = store.location.flatMap { $0.isUsable(at: date) ? $0.coordinate : nil }
        return StopsMapView(fallbackCenter: (usable ?? store.center)?.clLocationCoordinate2D,
                            followsLiveLocation: usable != nil, groups: store.mapGroups,
                            selectedStopID: selectedMapStop, onSelect: { selectedMapStop = $0 },
                            onTap: { stop, part, frame in tappedLabel(stop, part, at: frame) })
        .frame(width: width, height: width + strip)
        .popover(item: $mapChoice, attachmentAnchor: .rect(.rect(mapChoiceAnchor)), arrowEdge: .top) { choice in
            MapDirections(rows: choice.rows, direction: { displayDirection($0) }) { selection in
                pickedDirection = true
                mapChoice = nil
                onSelect(selection)
            }
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityIdentifier("home-map")
    }

    /// A direction as the list shows it.
    private func displayDirection(_ selection: StopLineSelection) -> String {
        Self.displayDirection(selection.line.direction, among: store.displayedOptions.map { $0.line.direction })
    }

    @ViewBuilder private func states(at date: Date) -> some View {
        if locationState == .failed, store.center != nil, store.location?.isUsable(at: date) != true {
            // A saved area stays on screen. Say once, at the top, that the
            // position behind it is not current, and offer to look again.
            Button(action: onLocate) {
                Label("Couldn't find your location · Try again", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }.foregroundStyle(.tint).accessibilityIdentifier("location-retry")
        }
        if locationState == .denied {
            Text("Location is off. Turn it on to see what leaves near you.").accessibilityIdentifier("location-status")
            settingsButton
        } else if let error = store.stopsError {
            Text(error).accessibilityIdentifier("stops-error")
            Button { Task { await onRefresh() } } label: {
                Label("Try again", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }.foregroundStyle(.tint)
        } else if locationState == .failed, store.center == nil {
            // Without a position there is nothing to show. Precise Location
            // off is the lasting cause, so Settings is offered beside a retry.
            Text("Couldn't find your location. Check that Precise Location is on.").accessibilityIdentifier("location-status")
            Button(action: onLocate) {
                Label("Try again", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }.foregroundStyle(.tint)
            settingsButton
        } else if store.home.checkedAt == nil, store.departuresError != nil {
            Button { Task { await onRefresh() } } label: {
                Label("Couldn't load departures · Retry", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }.foregroundStyle(.tint).accessibilityIdentifier("refresh-list")
        } else if store.home.checkedAt == nil, store.isLoadingStops || store.stopsCheckedAt == nil || !store.stops.isEmpty {
            Label("Finding departures…", systemImage: "clock").accessibilityIdentifier("board-status")
        } else if store.stops.isEmpty {
            Text("No stops within \(TransitFormat.distance(Double(TransitStore.radius)))").accessibilityIdentifier("empty-stops")
        } else {
            if store.needsListRefresh(at: date) { refreshBanner }
            if store.displayedOptions.isEmpty, store.home.missing.isEmpty {
                Text("Nothing leaves here in the next hour").accessibilityIdentifier("empty-departures")
            }
        }
    }

    private var refreshBanner: some View {
        Button { Task { await onRefresh() } } label: {
            if !store.home.missing.isEmpty {
                Label("Some times couldn't update · Retry", systemImage: "arrow.clockwise").frame(minHeight: 44)
            } else {
                let date = store.home.boards.values.map(\.checkedAt).min() ?? store.home.checkedAt ?? .now
                Label("Saved times from \(date.formatted(date: .omitted, time: .shortened)) · Refresh", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }
        }
        .foregroundStyle(.tint)
        .accessibilityIdentifier("refresh-list")
    }
    private var settingsButton: some View {
        Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
            Label("Open Settings", systemImage: "gear").frame(minHeight: 44)
        }.foregroundStyle(.tint)
    }
    private func row(_ selection: StopLineSelection, at date: Date, showStop: Bool = false) -> some View {
        StopRowView(selection: selection, board: store.home.boards[selection.id],
                    fresh: store.isHomeBoardFresh(for: selection, at: date), pinned: store.isPinned(selection), now: date,
                    onOpen: { onSelect(selection) }, onPin: { store.togglePin(selection) },
                    direction: Self.displayDirection(selection.line.direction, among: store.displayedOptions.map { $0.line.direction }), showStop: showStop,
                    badgeWidth: textSize.isAccessibilitySize ? nil : badgeColumn)
            .listRowInsets(.vertical, 0).listRowInsets(.horizontal, 16)
    }
    /// A pinned name sits on the list's own background, so the lines passing
    /// under it are hidden rather than showing through its text. iOS 26 also
    /// treats each text in a pinned header as a scroll-pocket element and
    /// shifts its colour slightly (measured 0 to 10 in light, 255 to 245 in
    /// dark), even with the edge effect hidden. Drawing the name as one layer
    /// keeps a pinned name exactly the colour of an unpinned one.
    struct StopHeader: ViewModifier {
        func body(content: Content) -> some View {
            content
                .drawingGroup()
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground))
                .listRowInsets(EdgeInsets())
        }
    }

    static func displayDirection(_ direction: String, among directions: [String]) -> String {
        let unique = Set(directions)
        guard unique.count >= 3, let prefix = direction.split(separator: " ").first,
              unique.allSatisfy({ $0.hasPrefix("\(prefix) ") && $0.count > prefix.count + 1 }) else { return direction }
        return String(direction.dropFirst(prefix.count + 1))
    }
}
