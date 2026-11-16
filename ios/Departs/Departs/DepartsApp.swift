import SwiftUI

@main
struct DepartsApp: App {
    @State private var session = TransitSession()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["DEPARTS_TEST_VIEWPORT"] == "1" {
                LayoutTestHost(session: session)
            } else {
                ContentView(session: session)
            }
            #else
            ContentView(session: session)
            #endif
        }
    }
}

/// Data, location requests and the refresh clock belong to the app. Each window
/// keeps its own navigation and contributes only the answers it is displaying.
@MainActor
@Observable
final class TransitSession {
    let store: TransitStore
    let locationService: LocationService
    private var windows: [UUID: WindowDemand] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var areaTask: Task<Void, Never>?
    @ObservationIgnored private var lastLocationDate: Date?

    struct WindowDemand {
        var showsList: Bool
        var selection: StopLineSelection?
    }

    init(store: TransitStore? = nil, locationService: LocationService = LocationService()) {
        self.store = store ?? TransitStore()
        self.locationService = locationService
    }

    func updateWindow(_ id: UUID, active: Bool, showsList: Bool, selection: StopLineSelection?) {
        let enteredForeground = active && windows[id] == nil
        windows[id] = active ? WindowDemand(showsList: showsList, selection: selection) : nil
        if windows.isEmpty {
            refreshTask?.cancel()
            refreshTask = nil
            locationTask?.cancel()
            locationTask = nil
            return
        }
        guard refreshTask == nil else {
            if enteredForeground {
                // Another window already owns the clock. Refresh this newly
                // active viewport now without starting a second clock.
                locationTask?.cancel()
                locationTask = Task { await refreshVisibleAnswers() }
            }
            return
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.store.location?.capturedAt.isRecent(at: .now, within: 45) != true {
                    self.locationService.requestLocation()
                }
                await self.refreshVisibleAnswers()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    func receivedLocation() {
        guard !windows.isEmpty, let fix = locationService.fix,
              fix.capturedAt != lastLocationDate else { return }
        lastLocationDate = fix.capturedAt
        locationTask?.cancel()
        locationTask = Task { await refreshVisibleAnswers() }
    }

    func refreshVisibleAnswers() async {
        let demands = Array(windows.values)
        guard !demands.isEmpty else { return }
        var seen = Set<String>()
        let selections = demands.compactMap(\.selection).filter { seen.insert($0.id).inserted }
        let showsList = demands.contains { $0.showsList }
        let fix = locationService.fix ?? store.location
        if let fix, fix.isUsable(at: .now) {
            await store.updateLocation(fix, showing: showsList ? nil : selections.first)
        } else if showsList {
            await store.refreshAnswers()
        }
        for selection in selections {
            guard !Task.isCancelled else { return }
            await store.refreshSelection(selection)
        }
    }

    func chooseArea(_ area: SearchArea) {
        locationTask?.cancel()
        areaTask?.cancel()
        areaTask = Task { await store.loadArea(area) }
    }

    func locate() {
        store.followsLocation = true
        locationService.requestLocation()
        if let fix = locationService.fix, fix.isUsable(at: .now) {
            areaTask?.cancel()
            locationTask?.cancel()
            locationTask = Task { await store.updateLocation(fix) }
        }
    }

    func refresh() async {
        if store.followsLocation { locationService.requestLocation() }
        if let area = store.area, store.stopsError != nil { await store.loadArea(area, radius: store.radius, forceRefresh: true) }
        else { await store.refreshAnswers(force: true) }
    }
}

#if DEBUG
/// Exercise exact container sizes, including widths below the iPad window
/// manager's minimum. Normal launches and Release builds never use this host.
private struct LayoutTestHost: View {
    let session: TransitSession
    @State private var width: CGFloat = 320
    @State private var height: CGFloat = 700

    var body: some View {
        GeometryReader { geometry in
            ContentView(session: session)
                .environment(\.horizontalSizeClass, width < 700 ? .compact : .regular)
                .environment(\.verticalSizeClass, height <= 400 ? .compact : .regular)
                .frame(width: min(width, geometry.size.width), height: min(height, geometry.size.height))
                .accessibilityIdentifier("layout-viewport")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.keyboard)
        .task {
            guard let base = ProcessInfo.processInfo.environment["DEPARTS_API_BASE_URL"].flatMap(URL.init(string:)) else { return }
            while !Task.isCancelled {
                do {
                    let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("test/viewport"))
                    let size = try JSONDecoder().decode(Viewport.self, from: data)
                    if (320...1200).contains(size.width), (320...900).contains(size.height) {
                        if width != size.width { width = size.width }
                        if height != size.height { height = size.height }
                    }
                    try await Task.sleep(for: .milliseconds(200))
                } catch { return }
            }
        }
    }
    private struct Viewport: Decodable { let width: Double; let height: Double }
}
#endif
