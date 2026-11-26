import SwiftUI
import CoreLocation

@main
struct DepartsApp: App {
    @State private var session = TransitSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
    }
}

/// Data, location requests and the refresh clock belong to the app. The window
/// owns navigation and reports which answers are visible.
@MainActor
@Observable
final class TransitSession {
    let store: TransitStore
    let locationService: LocationService
    private let authorizationStatus: () -> CLAuthorizationStatus
    private let waitForRefresh: () async throws -> Void
    private var windows: [UUID: WindowDemand] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var lastLocationDate: Date?

    struct WindowDemand {
        var showsList: Bool
        var selection: StopLineSelection?
    }

    init(store: TransitStore? = nil, locationService: LocationService = LocationService(),
         authorizationStatus: (() -> CLAuthorizationStatus)? = nil,
         waitForRefresh: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(30)) }) {
        let authorization = authorizationStatus ?? { locationService.authorizationStatus }
        self.authorizationStatus = authorization
        let liveClient = TransitClient.live { Self.allowsWalking(authorization()) }
        #if DEBUG
        var client = liveClient
        if let fixture = ProcessInfo.processInfo.environment["DEPARTS_TEST_WALKING_ROUTES"] {
            client.directions = { origin, destination in
                guard fixture == "straight" else { throw CancellationError() }
                let distance = origin.distance(to: destination)
                return WalkingRoute(
                    geometry: .init(type: "LineString", coordinates: [[origin.lon, origin.lat], [destination.lon, destination.lat]]),
                    duration: max(45, distance / 1.3), distance: distance
                )
            }
        }
        #else
        let client = liveClient
        #endif
        self.store = store ?? TransitStore(client: client)
        self.locationService = locationService
        self.waitForRefresh = waitForRefresh
        self.store.setWalkingDemand(showsList: false, selectedStops: [])
    }

    func updateWindow(_ id: UUID, active: Bool, showsList: Bool, selection: StopLineSelection?) {
        let enteredForeground = active && windows[id] == nil
        windows[id] = active ? WindowDemand(showsList: showsList, selection: selection) : nil
        synchronizeWalkingDemand(atForegroundEntry: true)
        if windows.isEmpty {
            refreshTask?.cancel()
            refreshTask = nil
            locationTask?.cancel()
            locationTask = nil
            return
        }
        guard refreshTask == nil else {
            if enteredForeground {
                // Only a second window gets here: with one window (O27) the clock stops when
                // the window leaves the foreground. If Departs supports several windows, a
                // window entering the foreground refreshes its answers without a second clock.
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
                do { try await self.waitForRefresh() } catch { return }
            }
        }
    }

    func receivedLocation() {
        if !Self.allowsWalking(authorizationStatus()) {
            locationTask?.cancel()
            synchronizeWalkingDemand()
            return
        }
        guard !windows.isEmpty, let fix = locationService.fix,
              fix.capturedAt != lastLocationDate else { return }
        lastLocationDate = fix.capturedAt
        locationTask?.cancel()
        locationTask = Task { await refreshVisibleAnswers() }
    }

    func refreshVisibleAnswers() async {
        let demands = Array(windows.values)
        guard !demands.isEmpty else { return }
        let allowsWalking = synchronizeWalkingDemand()
        var seen = Set<String>()
        let selections = demands.compactMap(\.selection).filter { seen.insert($0.id).inserted }
        let showsList = demands.contains { $0.showsList }
        let fix = allowsWalking ? (locationService.fix ?? store.location) : nil
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

    private static func allowsWalking(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined: return true
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    @discardableResult
    private func synchronizeWalkingDemand(atForegroundEntry: Bool = false) -> Bool {
        let status = authorizationStatus()
        guard Self.allowsWalking(status) else {
            store.setWalkingDemand(showsList: false, selectedStops: [])
            store.clearArea()
            return false
        }
        // Before the prompt is answered, keep the existing refresh-triggered
        // behavior without starting walks just because the window activated.
        store.setWalkingDemand(showsList: windows.values.contains(where: \.showsList),
                               selectedStops: windows.values.compactMap { $0.selection?.stop },
                               startWalks: atForegroundEntry && status != .notDetermined)
        return true
    }

    func locate() {
        locationService.requestLocation()
        if let fix = locationService.fix, fix.isUsable(at: .now) {
            locationTask?.cancel()
            locationTask = Task { await store.updateLocation(fix) }
        }
    }

    func refresh() async {
        locationService.requestLocation()
        if let center = store.center, store.stopsError != nil { await store.loadArea(center, forceRefresh: true) }
        else { await store.refreshAnswers(force: true) }
    }
}
