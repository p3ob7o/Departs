import SwiftUI

struct ContentView: View {
    let session: TransitSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowID = UUID()
    @State private var selected: StopLineSelection?
    @State private var sheet: PresentedSheet?
    @State private var navigation = RouteNavigation.shared

    private var store: TransitStore { session.store }
    private var demandKey: String { "\(scenePhase)-\(selected?.id ?? "")" }
    private enum PresentedSheet: Identifiable {
        case search, distantPins
        var id: String {
            switch self {
            case .search: "search"
            case .distantPins: "pins"
            }
        }
    }

    var body: some View {
        NavigationStack {
            NearbyStopsView(
                store: store, locationState: session.locationService.state,
                onSelect: select, onSearch: { sheet = .search }, onLocate: session.locate,
                onRefresh: session.refresh, onChooseArea: chooseArea,
                onDistantPins: { sheet = .distantPins }, interactionID: "\(windowID)-list")
                .navigationDestination(item: $selected) { selection in
                    DepartureDetailView(selection: selection, store: store)
                }
        }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .search:
                AreaSearchView(near: store.area?.coordinate, recentAreas: store.recentAreas,
                               onLocate: { sheet = nil; session.locate() }, onSelect: chooseArea)
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
            }
        }
        .onChange(of: session.locationService.state) { _, _ in session.receivedLocation() }
        .onChange(of: demandKey, initial: true) { _, _ in
            store.setPresentationActive(scenePhase == .active, presentationID: "\(windowID)")
            session.updateWindow(windowID, active: scenePhase == .active, showsList: selected == nil,
                                 selection: selected)
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
    private func select(_ selection: StopLineSelection) {
        selected = selection
    }
    private func openRequestedPin() {
        guard let key = navigation.pinnedRouteID else { return }
        if let pin = store.pins.first(where: { $0.id == key }) { select(pin) }
        navigation.pinnedRouteID = nil
    }
    private func chooseArea(_ area: SearchArea) {
        sheet = nil
        selected = nil
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
