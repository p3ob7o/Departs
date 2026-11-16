import SwiftUI

struct ContentView: View {
    let session: TransitSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var windowID = UUID()
    @State private var selected: StopLineSelection?
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var sheet: PresentedSheet?
    @State private var selectedMapStop: String?
    @State private var mapCardHeight: CGFloat = 0
    @State private var listScrollTarget: String?
    @State private var detailScrollTarget: String?
    @State private var navigation = RouteNavigation.shared

    private var store: TransitStore { session.store }
    private var showsList: Bool {
        sizeClass == .regular ? columns != .detailOnly : compactColumn == .sidebar
    }
    private var showsDetail: Bool { selected != nil && (sizeClass == .regular || compactColumn == .detail) }
    private var demandKey: String { "\(scenePhase)-\(showsList)-\(showsDetail)-\(selected?.id ?? "")" }

    private enum PresentedSheet: Identifiable {
        case search, stops, distantPins, route(StopLineSelection)
        var id: String {
            switch self {
            case .search: "search"
            case .stops: "stops"
            case .distantPins: "pins"
            case .route(let selection): "route-\(selection.id)"
            }
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            NearbyStopsView(
                store: store, locationState: session.locationService.state,
                onSelect: select, onSearch: { sheet = .search }, onLocate: session.locate,
                onRefresh: session.refresh, onChooseArea: chooseArea,
                onMap: { sheet = .stops }, onDistantPins: { sheet = .distantPins },
                visibilityID: "\(windowID)-list", scrollTarget: $listScrollTarget)
                .navigationSplitViewColumnWidth(min: 320, ideal: 402, max: 560)
        } detail: {
            if let selected {
                DepartureDetailView(
                    selection: selected, store: store, onSelect: select,
                    onMap: { sheet = .route(selected) },
                    interactionID: "\(windowID)-detail", scrollTarget: $detailScrollTarget)
            } else {
                ContentUnavailableView("Choose a departure", systemImage: "tram",
                                       description: Text("Select a line to see its departures and walking route."))
                    .navigationTitle("Departs")
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Presentation belongs to this stable window root, not a disappearing
        // column. Resizing or returning to the list cannot dismiss a sheet.
        .sheet(item: $sheet) { presented in
            switch presented {
            case .search:
                AreaSearchView(near: store.area?.coordinate, recentAreas: store.recentAreas,
                               onLocate: { sheet = nil; session.locate() }, onSelect: chooseArea)
            case .stops:
                stopsMapSheet
            case .distantPins:
                NavigationStack {
                    List(store.distantPins) { selection in
                        Button {
                            sheet = nil
                            select(selection)
                        } label: {
                            Text("\(selection.line.name) toward \(selection.line.direction) · \(selection.stop.name)")
                                .frame(minHeight: 44)
                        }
                    }
                    .modifier(ReadableList())
                    .navigationTitle("Pinned elsewhere").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done", systemImage: "checkmark") { sheet = nil } }
                }
            case .route(let selection):
                NavigationStack {
                    RouteMapView(
                        userCoordinate: (store.walkingOrigin ?? selection.stop.location).clLocationCoordinate2D,
                        stop: selection.stop, stopColor: StopPalette.modeColor(selection.line.type),
                        walkingRoute: store.walk(for: selection.stop)?.route, line: selection.line)
                        .navigationTitle("Walking route").navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Done", systemImage: "checkmark") { sheet = nil } }
                }
                .presentationDetents(textSize.isAccessibilitySize ? [.large] : [.medium, .large])
            }
        }
        .onChange(of: session.locationService.state) { _, _ in session.receivedLocation() }
        .onChange(of: demandKey, initial: true) { _, _ in
            store.setPresentationActive(scenePhase == .active, presentationID: "\(windowID)")
            session.updateWindow(windowID, active: scenePhase == .active, showsList: showsList,
                                 selection: showsDetail ? selected : nil)
            if scenePhase == .active { openRequestedPin() }
        }
        .onDisappear {
            session.updateWindow(windowID, active: false, showsList: false, selection: nil)
            store.clearPresentation("\(windowID)")
        }
        .onChange(of: navigation.pinnedRouteID) { _, _ in
            if scenePhase == .active { openRequestedPin() }
        }
        .onChange(of: store.pins) { _, _ in DepartsShortcuts.updateAppShortcutParameters() }
        .sensoryFeedback(.selection, trigger: store.pins.map(\.id))
        .onOpenURL { url in
            guard let key = RouteNavigation.pinID(from: url), let pin = store.pins.first(where: { $0.id == key }) else { return }
            select(pin)
        }
    }

    private var stopsMapSheet: some View {
        NavigationStack {
            if let area = store.area {
                GeometryReader { geometry in
                    StopsMapView(userCoordinate: area.coordinate.clLocationCoordinate2D, groups: store.groups,
                                 radius: store.radius, selectedStopID: selectedMapStop, onSelect: { selectedMapStop = $0 })
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if let group = store.groups.first(where: { $0.id == selectedMapStop }) {
                                // Leave at least half the pane for the map, including
                                // compact-height windows with accessibility text.
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(group.name).font(.headline)
                                        Text(group.lines.map(\.name).joined(separator: " · ")).font(.subheadline)
                                        Button {
                                            listScrollTarget = group.id
                                            compactColumn = .sidebar
                                            columns = .all
                                            sheet = nil
                                        } label: {
                                            Label("Show in list", systemImage: "list.bullet").frame(minHeight: 48)
                                        }
                                    }.padding().frame(maxWidth: 600, alignment: .leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapCardHeight = $0 }
                                }
                                .frame(height: min(geometry.size.height / 2, max(48, mapCardHeight)))
                                .clipped()
                                .background(.regularMaterial)
                                .accessibilityIdentifier("selected-stop-card")
                            }
                        }
                }
                .navigationTitle("Nearby stops").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done", systemImage: "checkmark") { sheet = nil } }
            }
        }
        .presentationDetents(textSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    private func select(_ selection: StopLineSelection) {
        if selected?.id != selection.id { detailScrollTarget = nil }
        selected = selection
        compactColumn = .detail
    }

    private func openRequestedPin() {
        guard let key = navigation.pinnedRouteID else { return }
        if let pin = store.pins.first(where: { $0.id == key }) { select(pin) }
        navigation.pinnedRouteID = nil
    }

    private func chooseArea(_ area: SearchArea) {
        sheet = nil
        selected = nil
        compactColumn = .sidebar
        session.chooseArea(area)
    }
}

/// Cap text, not bars or the scroll container, so system controls and indicators
/// remain attached to the pane edges as its width changes.
struct ReadableList: ViewModifier {
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .contentMargins(.horizontal, max(0, (width - 640) / 2), for: .scrollContent)
    }
}

#if DEBUG
private struct ResizablePreview: View {
    let width: CGFloat
    @State private var session = TransitSession(store: PreviewData.makeStore())

    var body: some View {
        ContentView(session: session)
            .environment(\.horizontalSizeClass, width < 700 ? .compact : .regular)
            .environment(\.scenePhase, .inactive)
            .task {
                await session.store.updateLocation(.init(coordinate: PreviewData.userCoordinate,
                                                         capturedAt: .now, accuracy: 10))
            }
    }
}

#Preview("320 points", traits: .fixedLayout(width: 320, height: 667)) { ResizablePreview(width: 320) }
#Preview("402 points", traits: .fixedLayout(width: 402, height: 874)) { ResizablePreview(width: 402) }
#Preview("466 points", traits: .fixedLayout(width: 466, height: 956)) { ResizablePreview(width: 466) }
#Preview("669 points · compact height", traits: .fixedLayout(width: 669, height: 375)) { ResizablePreview(width: 669) }
#Preview("834 points", traits: .fixedLayout(width: 834, height: 1194)) { ResizablePreview(width: 834) }
#Preview("1024 points", traits: .fixedLayout(width: 1024, height: 768)) { ResizablePreview(width: 1024) }
#endif
