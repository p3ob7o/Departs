import SwiftUI

struct NearbyStopsView: View {
    @Bindable var store: TransitStore
    let locationState: LocationService.State
    let onSelect: (StopLineSelection) -> Void
    let onSearch: () -> Void
    let onLocate: () -> Void
    let onRefresh: () async -> Void
    var onChooseArea: (SearchArea) -> Void = { _ in }
    var onMap: () -> Void = {}
    var onDistantPins: () -> Void = {}
    var visibilityID = "nearby"
    @Binding var scrollTarget: String?
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.openURL) private var openURL
    @AppStorage("departs.pinHintSeen", store: TransitPersistence().defaults) private var hintSeen = false
    @State private var expandedIdle: Set<String> = []
    @State private var countdownStart = Date.now

    var body: some View {
        ScrollViewReader { proxy in
        TimelineView(.periodic(from: countdownStart, by: 15)) { timeline in
            // Board arrivals also redraw between ticks. Do not compare a new
            // check timestamp with an older timeline tick and call it saved.
            let date = max(timeline.date, Date.now)
            List {
                if store.area != nil {
                Section {
                    Text(context(at: date)).font(.caption2)
                        .accessibilityIdentifier("board-status")
                    if needsRefresh(at: date) {
                        Button { Task { await onRefresh() } } label: {
                            Label("Refresh now", systemImage: "arrow.clockwise").frame(minHeight: 44)
                        }.accessibilityIdentifier("refresh-list")
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                }
                if case .denied = locationState {
                    Section {
                        Text("Location is off. Choose an area or use a pinned route.").accessibilityIdentifier("location-status")
                        Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                            Text("Open Settings").frame(minHeight: 44)
                        }
                    }
                }
                if case .requesting = locationState, store.followsLocation {
                    Section { Label("Finding your location…", systemImage: "location").accessibilityIdentifier("location-status") }
                }
                if case .failed = locationState, store.followsLocation {
                    Section {
                        Text("Couldn't find your location. Choose an area or try again.").accessibilityIdentifier("location-status")
                        Button(action: onLocate) { Label("Try location again", systemImage: "location").frame(minHeight: 44) }
                    }
                }
                if let error = store.stopsError {
                    Section {
                        Text(error)
                        Button { Task { await onRefresh() } } label: { Text("Try again").frame(minHeight: 44) }
                    }
                }
                if !store.nearbyPins.isEmpty || !store.distantPins.isEmpty {
                    Section("Pinned") {
                        ForEach(store.nearbyPins) { row($0, at: date, pinnedSection: true) }
                        if !store.distantPins.isEmpty {
                            Button(action: onDistantPins) {
                                Text("Pinned elsewhere (\(store.distantPins.count))").frame(minHeight: 44)
                            }
                        }
                    }
                }
                ForEach(store.groups) { group in
                    Section {
                        let active = group.active.filter { !store.isPinned($0) }
                        let idle = group.idle.filter { !store.isPinned($0) }
                        ForEach(active) { row($0, at: date) }
                        if !idle.isEmpty {
                            DisclosureGroup(isExpanded: Binding(get: { expandedIdle.contains(group.id) }, set: { if $0 { expandedIdle.insert(group.id) } else { expandedIdle.remove(group.id) } })) {
                                ForEach(idle) { row($0, at: date, idle: true) }
                            } label: {
                                Text(TransitFormat.idleLines(idle.count, limited: idle.contains { store.boards[$0.id]?.coverageLimit != nil }))
                                    .font(.subheadline).frame(minHeight: 44)
                            }
                            .modifier(VisibleStops(store: store, stops: group.stops, token: "\(visibilityID)-idle-\(group.id)"))
                            .listRowInsets(.vertical, 0).listRowInsets(.horizontal, 16)
                        }
                    } header: {
                        HStack {
                            Text(group.name).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
                            if !textSize.isAccessibilitySize, let walk = group.stops.compactMap({ store.walk(for: $0, at: date) }).min(by: { $0.route.duration < $1.route.duration }) {
                                Text("· \(TransitFormat.walk(walk.route, fromCurrentLocation: store.location?.isUsable(at: date) == true))").fontWeight(.regular)
                            }
                        }
                        .font(.subheadline).textCase(nil)
                        .id(group.id)
                        .modifier(VisibleStops(store: store, stops: group.stops, token: "\(visibilityID)-header-\(group.id)"))
                    }
                    if group.id == store.groups.first?.id, !hintSeen, store.pins.isEmpty {
                        Section {
                            Button { hintSeen = true } label: {
                                Label("Swipe or hold to pin. Got it", systemImage: "pin").font(.footnote).frame(minHeight: 44)
                            }.accessibilityIdentifier("pin-hint")
                                .listRowInsets(.vertical, 0).listRowInsets(.horizontal, 16)
                        }
                    }
                }
                if store.groups.isEmpty {
                    Section {
                        if store.isLoadingStops { ProgressView("Finding nearby options…") }
                        else if store.area != nil { ContentUnavailableView("No stops in this area", systemImage: "tram", description: Text("Search farther or choose another area.")) }
                        else { ContentUnavailableView("What’s leaving?", systemImage: "tram", description: Text("Choose an area or use your location to find departures.")) }
                    }
                }
                if store.canSearchFarther {
                    Button { Task { await store.searchFarther() } } label: {
                        Text("Search farther · \(TransitFormat.distance(store.radius == 400 ? 800 : 1600))").frame(minHeight: 44)
                    }.foregroundStyle(.tint).disabled(store.isLoadingStops).accessibilityIdentifier("search-farther")
                }
            }
            .listStyle(.plain)
            .modifier(ReadableList())
            .accessibilityIdentifier("nearby-list")
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.defaultMinListHeaderHeight, 0)
            .listSectionSpacing(0)
            .contentMargins(.top, 0, for: .scrollContent)
            .onScrollPhaseChange { _, phase in store.setInteracting(phase != .idle, presentationID: visibilityID) }
            .onDisappear { store.clearPresentation(visibilityID) }
            .refreshable { await onRefresh() }
        }
        .navigationTitle(areaTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Button("Current location", systemImage: "location", action: onLocate)
            ForEach(Array(store.recentAreas.enumerated()), id: \.offset) { _, area in
                Button(area.name, systemImage: "clock.arrow.circlepath") { onChooseArea(area) }
            }
            Button("Search for a place…", systemImage: "magnifyingglass", action: onSearch)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Choose area", systemImage: "magnifyingglass", action: onSearch)
                    .accessibilityIdentifier("choose-area")
                Button("Use my location", systemImage: store.followsLocation ? "location.fill" : "location", action: onLocate)
                    .accessibilityValue(store.followsLocation ? String(localized: "Following your location") : String(localized: "Showing a chosen or saved area"))
                Button("Show nearby map", systemImage: "map", action: onMap)
            }
        }
        .onChange(of: scrollTarget) { _, target in
            guard let target else { return }
            proxy.scrollTo(target, anchor: .top)
            scrollTarget = nil
        }
        }
    }

    private var areaTitle: String {
        store.area?.source == .chosen ? store.area!.name : store.location?.isUsable(at: .now) == true ? String(localized: "Near you") : store.area == nil ? "Departs" : String(localized: "Last area")
    }

    private func row(_ selection: StopLineSelection, at date: Date, pinnedSection: Bool = false, idle: Bool = false) -> some View {
        StopRowView(selection: selection, board: store.boards[selection.id], walk: store.walk(for: selection.stop, at: date),
                    advice: store.advice(for: selection, at: date), loading: store.loadingBoards.contains(selection.id),
                    failed: store.boardErrors.contains(selection.id), fresh: store.isBoardFresh(for: selection, at: date),
                    fromCurrentLocation: store.location?.isUsable(at: date) == true, pinned: store.isPinned(selection), now: date,
                    onOpen: { onSelect(selection) }, onPin: { store.togglePin(selection); hintSeen = true }, direction: displayDirection(selection.line.direction), showStop: pinnedSection, idle: idle)
            .modifier(VisibleStops(store: store, stops: [selection.stop], token: "\(visibilityID)-\(selection.id)"))
            .listRowInsets(.vertical, 4).listRowInsets(.horizontal, 16)
    }
    private func displayDirection(_ direction: String) -> String {
        Self.displayDirection(direction, among: store.stops.flatMap(\.lines).map(\.direction))
    }
    static func displayDirection(_ direction: String, among directions: [String]) -> String {
        let unique = Set(directions)
        guard unique.count >= 3, let prefix = direction.split(separator: " ").first,
              unique.allSatisfy({ $0.hasPrefix("\(prefix) ") && $0.count > prefix.count + 1 }) else { return direction }
        return String(direction.dropFirst(prefix.count + 1))
    }
    private func needsRefresh(at date: Date) -> Bool {
        store.needsListRefresh(at: date)
    }
    private func context(at date: Date) -> String {
        let boards = store.displayedOptions.compactMap { store.boards[$0.id] }
        let timestamp = boards.map(\.checkedAt).min()
        let fresh = !needsRefresh(at: date)
        let radius = TransitFormat.distance(Double(store.radius))
        if textSize.isAccessibilitySize && fresh {
            return String(localized: "Within \(radius)")
        }
        let status = timestamp.map { TimeFormatter.freshness($0, now: date, fresh: fresh) }
            ?? (fresh ? String(localized: "Checking departures…") : String(localized: "Couldn't update departures"))
        return String(localized: "Within \(radius) · \(status)")
    }
}

private struct VisibleStops: ViewModifier {
    let store: TransitStore
    let stops: [NearbyStop]
    let token: String

    func body(content: Content) -> some View {
        content.onScrollVisibilityChange(threshold: 0.01) { visible in
            store.setVisible(stops, elementID: token, visible: visible)
        }
        .onDisappear { store.setVisible(stops, elementID: token, visible: false) }
    }
}
