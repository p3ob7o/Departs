import SwiftUI

struct ContentView: View {
    let session: TransitSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var windowID = UUID()
    @State private var selected: StopLineSelection?
    @State private var showsDistantPins = false
    @State private var navigation = RouteNavigation.shared

    private var store: TransitStore { session.store }
    private var demandKey: String { "\(scenePhase)-\(selected?.id ?? "")" }

    var body: some View {
        NavigationStack {
            NearbyStopsView(
                store: store, locationState: session.locationService.state,
                onSelect: select, onLocate: session.locate, onRefresh: session.refresh,
                onDistantPins: { showsDistantPins = true }, interactionID: "\(windowID)-list")
                .navigationDestination(item: $selected) { selection in
                    DepartureDetailView(selection: selection, store: store)
                }
        }
        .sheet(isPresented: $showsDistantPins) {
            NavigationStack {
                List(store.distantPins) { selection in
                    Button {
                        showsDistantPins = false
                        select(selection)
                    } label: {
                        Text("\(selection.line.name) toward \(selection.line.direction) · \(selection.stop.name)")
                            .frame(minHeight: 44)
                    }
                }
                .modifier(ReadableList())
                .navigationTitle("Pinned elsewhere").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done", systemImage: "checkmark") { showsDistantPins = false } }
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
#Preview("Home") {
    ContentView(session: TransitSession(store: PreviewData.makeStore()))
        .environment(\.scenePhase, .inactive)
}
#endif
