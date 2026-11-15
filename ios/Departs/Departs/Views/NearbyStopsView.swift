import SwiftUI

struct NearbyStopsView: View {
    @Bindable var store: TransitStore
    let locationState: LocationService.State
    let onSelect: (StopLineSelection) -> Void
    let onSearch: () -> Void
    let onLocate: () -> Void
    let onRefresh: () async -> Void
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.openURL) private var openURL
    @AppStorage("departs.pinHintSeen") private var hintSeen = false
    @State private var showingMap = false
    @State private var showingDistantPins = false
    @State private var expandedIdle: Set<String> = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            List {
                Section {
                    Text(context(at: timeline.date)).font(.caption2)
                        .accessibilityIdentifier("board-status")
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                if case .denied = locationState {
                    Section {
                        Text("Location is off. Choose an area or use a pinned route.").accessibilityIdentifier("location-status")
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.frame(minHeight: 44)
                    }
                }
                if !store.nearbyPins.isEmpty || !store.distantPins.isEmpty {
                    Section("Pinned") {
                        ForEach(store.nearbyPins) { row($0, at: timeline.date, pinnedSection: true) }
                        if !store.distantPins.isEmpty {
                            Button("Pinned elsewhere (\(store.distantPins.count))") { showingDistantPins = true }
                                .frame(minHeight: 44)
                        }
                    }
                }
                ForEach(store.groups) { group in
                    Section {
                        let unpinned = group.options.filter { !store.isPinned($0) }
                        let active = unpinned.filter { store.runningIDs.contains($0.id) || store.boards[$0.id] == nil || store.boardErrors.contains($0.id) }
                        let idle = unpinned.filter { !store.runningIDs.contains($0.id) && store.boards[$0.id] != nil && !store.boardErrors.contains($0.id) }
                        ForEach(active) { row($0, at: timeline.date) }
                        if !idle.isEmpty {
                            DisclosureGroup(isExpanded: Binding(get: { expandedIdle.contains(group.id) }, set: { if $0 { expandedIdle.insert(group.id) } else { expandedIdle.remove(group.id) } })) {
                                ForEach(idle) { row($0, at: timeline.date) }
                            } label: { Text("\(idle.count) lines with nothing soon").font(.subheadline).frame(minHeight: 44) }
                        }
                    } header: {
                        HStack {
                            Text(group.name).font(.caption).fixedSize(horizontal: false, vertical: true)
                            if !textSize.isAccessibilitySize, let walk = group.stops.compactMap({ store.walk(for: $0, at: timeline.date) }).first {
                                Text("· \(max(1, walk.route.walkingMinutes)) min walk")
                            }
                        }
                        .task { await store.loadGroup(group) }
                    }
                }
                if store.groups.isEmpty {
                    Section {
                        if store.isLoadingStops { ProgressView("Finding nearby options…") }
                        else { ContentUnavailableView("What’s leaving?", systemImage: "tram", description: Text("Choose an area or use your location to find departures.")) }
                    }
                }
                if !hintSeen && !store.groups.isEmpty {
                    Section {
                        Button { hintSeen = true } label: {
                            Label("Swipe or hold a route to pin it. Got it", systemImage: "pin").font(.footnote).frame(minHeight: 44)
                        }
                    }
                }
                if let error = store.stopsError {
                    Section {
                        Text(error)
                        Button("Try again") { Task { await onRefresh() } }.frame(minHeight: 44)
                    }
                }
                if store.canSearchFarther {
                    Button { Task { await store.searchFarther() } } label: {
                        Text("Search farther · \(store.radius == 400 ? "800 m" : "1.6 km")").frame(minHeight: 44)
                    }.accessibilityIdentifier("search-farther")
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.defaultMinListHeaderHeight, 0)
            .listSectionSpacing(0)
            .contentMargins(.top, 0, for: .scrollContent)
            .onScrollPhaseChange { _, phase in store.interacting = phase != .idle }
            .refreshable { await onRefresh() }
        }
        .navigationTitle(store.area?.source == .chosen ? store.area!.name : "Near you")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Button("Current location", systemImage: "location", action: onLocate)
            Button("Search for a place…", systemImage: "magnifyingglass", action: onSearch)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Choose area", systemImage: "magnifyingglass", action: onSearch).accessibilityIdentifier("choose-area")
                Button("Use my location", systemImage: store.followsLocation ? "location.fill" : "location", action: onLocate)
                Button("Show nearby map", systemImage: "map") { showingMap = true }
            }
        }
        .sheet(isPresented: $showingMap) {
            if let area = store.area {
                NavigationStack {
                    StopsMapView(userCoordinate: area.coordinate.clLocationCoordinate2D, stops: store.stops,
                                 stopColors: Dictionary(uniqueKeysWithValues: store.stops.enumerated().map { ($0.element.id, StopPalette.color(at: $0.offset)) }), radius: store.radius)
                        .navigationTitle("Nearby stops")
                        .toolbar { Button("Done") { showingMap = false } }
                }
            }
        }
        .sheet(isPresented: $showingDistantPins) {
            NavigationStack {
                List(store.distantPins) { selection in
                    Button("\(selection.line.name) toward \(selection.line.direction) · \(selection.stop.name)") {
                        showingDistantPins = false
                        onSelect(selection)
                    }
                }.navigationTitle("Pinned elsewhere")
                    .toolbar { Button("Done") { showingDistantPins = false } }
            }
        }
    }

    private func row(_ selection: StopLineSelection, at date: Date, pinnedSection: Bool = false) -> some View {
        StopRowView(selection: selection, board: store.boards[selection.id], walk: store.walk(for: selection.stop, at: date),
                    advice: store.advice(for: selection, at: date), loading: store.loadingBoards.contains(selection.id),
                    failed: store.boardErrors.contains(selection.id), fresh: store.isBoardFresh(for: selection, at: date),
                    fromCurrentLocation: store.location?.isUsable(at: date) == true, pinned: store.isPinned(selection), now: date,
                    onOpen: { onSelect(selection) }, onPin: { store.togglePin(selection) }, direction: displayDirection(selection.line.direction), showStop: pinnedSection)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
    private func displayDirection(_ direction: String) -> String {
        // Only remove a common locality known from the selected area or stop names.
        let words = direction.split(separator: " ")
        guard words.count > 1, let prefix = words.first else { return direction }
        let directions = store.stops.flatMap(\.lines).map(\.direction)
        guard directions.count > 1, directions.allSatisfy({ $0.hasPrefix("\(prefix) ") }),
              prefix == "Wien" || store.area?.name == String(prefix) else { return direction }
        return String(direction.dropFirst(prefix.count + 1))
    }
    private func context(at date: Date) -> String {
        let boards = store.stops.flatMap(\.lineSelections).compactMap { store.boards[$0.id] }
        let timestamp = boards.map(\.checkedAt).min()
        let fresh = store.stops.flatMap(\.lineSelections).filter { store.boards[$0.id] != nil }.allSatisfy { store.isBoardFresh(for: $0, at: date) }
        let status = timestamp.map { TimeFormatter.freshness($0, now: date, fresh: fresh) } ?? "Checking departures…"
        return "Within \(store.radius) m · \(status)"
    }
}
