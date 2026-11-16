import SwiftUI

struct NearbyStopsView: View {
    @Bindable var store: TransitStore
    let locationState: LocationService.State
    let onSelect: (StopLineSelection) -> Void
    let onSearch: () -> Void
    let onLocate: () -> Void
    let onRefresh: () async -> Void
    var onChooseArea: (SearchArea) -> Void = { _ in }
    var onDistantPins: () -> Void = {}
    var interactionID = "nearby"
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.openURL) private var openURL
    @State private var selectedMapStop: String?
    @State private var countdownStart = Date.now

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if !textSize.isAccessibilitySize { map(width: geometry.size.width, proxy: proxy) }
                    TimelineView(.periodic(from: countdownStart, by: 15)) { timeline in
                        let date = max(timeline.date, Date.now)
                        List {
                            if textSize.isAccessibilitySize {
                                map(width: geometry.size.width, proxy: proxy)
                                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).id("home-top")
                            } else {
                                Color.clear.frame(height: 1).listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden).accessibilityHidden(true).id("home-top")
                            }
                            states(at: date)
                            if !store.nearbyPins.isEmpty || !store.distantPins.isEmpty {
                                Section {
                                    ForEach(store.nearbyPins) { row($0, at: date, showStop: true) }
                                    if !store.distantPins.isEmpty {
                                        Button(action: onDistantPins) {
                                            Label("Pinned elsewhere (\(store.distantPins.count))", systemImage: "pin")
                                                .frame(minHeight: 44)
                                        }.foregroundStyle(.tint)
                                    }
                                } header: { Text("Pinned").foregroundStyle(Color.primary).textCase(nil) }
                                .id("pinned")
                            }
                            ForEach(store.groups) { group in
                                Section {
                                    ForEach(group.active) { row($0, at: date) }
                                    if group.hasMissingBoard {
                                        Button { Task { await onRefresh() } } label: {
                                            Label("Couldn't load this stop · Retry", systemImage: "arrow.clockwise")
                                                .frame(minHeight: 44)
                                        }.foregroundStyle(.tint).accessibilityIdentifier("retry-stop")
                                    }
                                } header: {
                                    let layout = textSize.isAccessibilitySize
                                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
                                    layout {
                                        Text(group.name).fontWeight(.semibold).foregroundStyle(Color.primary)
                                        if let walk = store.walk(for: group, at: date) {
                                            Text(TransitFormat.walk(walk.route, fromCurrentLocation: store.location?.isUsable(at: date) == true))
                                                .foregroundStyle(StopPalette.secondaryText)
                                        }
                                    }
                                    .font(.subheadline).textCase(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("stop-section")
                                    .id(group.id)
                                }
                            }
                            if store.canSearchFarther, !store.isLoadingStops, store.home.checkedAt != nil {
                                searchFarther
                            }
                        }
                        .listStyle(.plain)
                        .id(store.areaRevision)
                        .environment(\.defaultMinListRowHeight, 0)
                        .environment(\.defaultMinListHeaderHeight, 0)
                        .listSectionSpacing(0)
                        .contentMargins(.top, 0, for: .scrollContent)
                        .accessibilityIdentifier("nearby-list")
                        .onScrollPhaseChange { _, phase in store.setInteracting(phase != .idle, presentationID: interactionID) }
                        .onDisappear { store.clearPresentation(interactionID) }
                        .refreshable { await onRefresh() }
                    }
                }
                .onChange(of: store.areaRevision) { _, _ in
                    selectedMapStop = nil
                    proxy.scrollTo("home-top", anchor: .top)
                }
            }
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
                    .accessibilityLabel(String(localized: "Use my location. \(locationValue)."))
                    .accessibilityIdentifier("locate")
            }
        }
    }

    private func map(width: CGFloat, proxy: ScrollViewProxy) -> some View {
        StopsMapView(userCoordinate: store.area?.coordinate.clLocationCoordinate2D, groups: store.mapGroups,
                     radius: store.radius, selectedStopID: selectedMapStop) { selected in
            selectedMapStop = selected
            guard let group = store.mapGroups.first(where: { $0.id == selected }) else { return }
            if group.active.count == 1, let selection = group.active.first { onSelect(selection) }
            else {
                let target = group.active.allSatisfy { store.isPinned($0) } ? "pinned" : group.id
                proxy.scrollTo(target, anchor: .top)
            }
        }
        .frame(width: width, height: width)
        .accessibilityIdentifier("home-map")
    }

    @ViewBuilder private func states(at date: Date) -> some View {
        if let error = store.stopsError {
            Text(error).accessibilityIdentifier("stops-error")
            Button { Task { await onRefresh() } } label: {
                Label("Try again", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }.foregroundStyle(.tint)
        } else if locationState == .denied, store.area == nil {
            Text("Location is off. Choose an area or use a pinned route.").accessibilityIdentifier("location-status")
            Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                Label("Open Settings", systemImage: "gear").frame(minHeight: 44)
            }.foregroundStyle(.tint)
            chooseAreaButton
        } else if store.home.checkedAt == nil, store.departuresError != nil {
            Button { Task { await onRefresh() } } label: {
                Label("Couldn't load departures · Retry", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }.foregroundStyle(.tint).accessibilityIdentifier("refresh-list")
        } else if store.isLoadingStops || store.home.checkedAt == nil && (store.stopsCheckedAt == nil || !store.stops.isEmpty) {
            Label("Finding departures…", systemImage: "clock").accessibilityIdentifier("board-status")
            if case .failed = locationState, store.area == nil {
                Text("Couldn't find your location. Choose an area or try again.")
                chooseAreaButton
            }
        } else if store.stops.isEmpty {
            Text("No stops within \(TransitFormat.distance(Double(store.radius)))").accessibilityIdentifier("empty-stops")
            if store.canSearchFarther { searchFarther }
            chooseAreaButton
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
    private var chooseAreaButton: some View {
        Button(action: onSearch) { Label("Choose an area", systemImage: "magnifyingglass").frame(minHeight: 44) }
            .foregroundStyle(.tint)
    }
    private var searchFarther: some View {
        Button { Task { await store.searchFarther() } } label: {
            Label("Search farther · \(TransitFormat.distance(store.radius == 400 ? 800 : 1600))", systemImage: "arrow.up.left.and.arrow.down.right")
                .frame(minHeight: 44)
        }.foregroundStyle(.tint).disabled(store.isLoadingStops).accessibilityIdentifier("search-farther")
    }
    private var areaTitle: String {
        store.area?.source == .chosen ? store.area!.name : store.location?.isUsable(at: .now) == true ? String(localized: "Near you") : store.area == nil ? "Departs" : String(localized: "Last area")
    }
    private var locationValue: String {
        locationState == .denied ? String(localized: "Location is off") : store.followsLocation
            ? String(localized: "Following your location") : String(localized: "Showing a chosen or saved area")
    }
    private func row(_ selection: StopLineSelection, at date: Date, showStop: Bool = false) -> some View {
        StopRowView(selection: selection, board: store.home.boards[selection.id],
                    fresh: store.isHomeBoardFresh(for: selection, at: date), pinned: store.isPinned(selection), now: date,
                    onOpen: { onSelect(selection) }, onPin: { store.togglePin(selection) },
                    direction: Self.displayDirection(selection.line.direction, among: store.displayedOptions.map { $0.line.direction }), showStop: showStop)
            .listRowInsets(.vertical, 0).listRowInsets(.horizontal, 16)
    }
    static func displayDirection(_ direction: String, among directions: [String]) -> String {
        let unique = Set(directions)
        guard unique.count >= 3, let prefix = direction.split(separator: " ").first,
              unique.allSatisfy({ $0.hasPrefix("\(prefix) ") && $0.count > prefix.count + 1 }) else { return direction }
        return String(direction.dropFirst(prefix.count + 1))
    }
}
