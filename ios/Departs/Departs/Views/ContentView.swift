import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var locationService = LocationService()
    @State private var store = TransitStore()
    @State private var selected: StopLineSelection?
    @State private var searching = false
    @State private var areaTask: Task<Void, Never>?
    @State private var locationTask: Task<Void, Never>?
    @State private var navigation = RouteNavigation.shared

    private var refreshKey: String {
        "\(scenePhase == .active)-\(selected?.id ?? "nearby")"
    }

    var body: some View {
        NavigationStack {
            NearbyStopsView(store: store, locationState: locationService.state,
                            onSelect: { selected = $0 }, onSearch: { searching = true },
                            onLocate: locate, onRefresh: refresh)
                .navigationDestination(item: $selected) { selection in
                    DepartureDetailView(selection: selection, store: store)
                }
        }
        .sheet(isPresented: $searching) {
            AreaSearchView(near: store.area?.coordinate) { area in
                searching = false
                selected = nil
                locationTask?.cancel()
                areaTask?.cancel()
                areaTask = Task { await store.loadArea(area) }
            }
        }
        .onChange(of: locationService.state) { _, state in
            guard scenePhase == .active, case .located = state, let fix = locationService.fix else { return }
            locationTask?.cancel()
            locationTask = Task { await store.updateLocation(fix, showing: selected) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { areaTask?.cancel(); locationTask?.cancel() }
        }
        .onChange(of: navigation.pinnedRouteID) { _, _ in openRequestedPin() }
        .onChange(of: store.pins) { _, _ in DepartsShortcuts.updateAppShortcutParameters() }
        .onOpenURL { url in
            guard let key = RouteNavigation.pinID(from: url) else { return }
            navigation.pinnedRouteID = key
        }
        .task(id: refreshKey) {
            guard scenePhase == .active else { return }
            openRequestedPin()
            if store.location?.capturedAt.isRecent(at: .now, within: 45) != true { locationService.requestLocation() }
            await refreshVisibleAnswers()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if store.location?.capturedAt.isRecent(at: .now, within: 45) != true { locationService.requestLocation() }
                await refreshVisibleAnswers()
            }
        }
    }

    private func openRequestedPin() {
        guard let key = navigation.pinnedRouteID else { return }
        selected = store.pins.first { $0.id == key }
        navigation.pinnedRouteID = nil
    }

    private func refreshVisibleAnswers() async {
        // A fix may arrive while a permission sheet temporarily makes the scene inactive.
        if let fix = locationService.fix, fix.isUsable(at: .now) {
            await store.updateLocation(fix, showing: selected)
        } else if let selected { await store.refreshSelection(selected) }
        else if let fix = store.location, fix.isUsable(at: .now) {
            await store.updateLocation(fix)
        } else { await store.refreshAnswers() }
    }

    private func locate() {
        store.followsLocation = true
        locationService.requestLocation()
        if let fix = locationService.fix, fix.isUsable(at: .now) {
            areaTask?.cancel()
            locationTask?.cancel()
            locationTask = Task { await store.updateLocation(fix) }
        }
    }

    private func refresh() async {
        if store.followsLocation { locationService.requestLocation() }
        if let area = store.area { await store.loadArea(area, radius: store.radius, forceRefresh: true) }
        else { await store.refreshAnswers(force: true) }
    }
}

#Preview { ContentView() }
