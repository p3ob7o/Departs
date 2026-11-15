import SwiftUI

struct NearbyStopsView: View {
    @Bindable var store: TransitStore
    let locationState: LocationService.State
    let onSelect: (StopLineSelection) -> Void
    let onSearch: () -> Void
    let onLocate: () -> Void
    let onRefresh: () async -> Void
    @Environment(\.openURL) private var openURL
    @State private var showingMap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("What’s leaving?").font(.largeTitle.bold())
                    Text(areaLabel).font(.subheadline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 12) {
                    Button(action: onSearch) { Label("Choose area", systemImage: "magnifyingglass").frame(minHeight: 44) }
                        .accessibilityIdentifier("choose-area")
                    Spacer()
                    Button(action: onLocate) { Image(systemName: store.followsLocation ? "location.fill" : "location").frame(width: 44, height: 44) }
                        .accessibilityLabel("Use my location")
                        .accessibilityValue(store.followsLocation ? "Following your location" : "Showing a chosen or saved area")
                    if store.area != nil {
                        Button { showingMap = true } label: { Image(systemName: "map").frame(width: 44, height: 44) }
                            .accessibilityLabel("Show nearby map")
                    }
                }

                RouteFilter(pinned: $store.favoritesOnly, count: store.pins.count)
                    .frame(height: 44)


                if let message = statusMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("location-status")
                }
                if case .denied = locationState {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: { Text("Open Settings").frame(minWidth: 44, minHeight: 44) }
                }
                if let error = store.stopsError, !store.favoritesOnly {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.subheadline)
                        Button { Task { await onRefresh() } } label: { Text("Try again").frame(minWidth: 44, minHeight: 44) }
                    }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }

                if store.visibleSelections.isEmpty {
                    emptyContent
                } else {
                    TimelineView(.periodic(from: .now, by: 15)) { timeline in
                        LazyVStack(spacing: 12) {
                            ForEach(store.visibleSelections) { selection in
                                StopRowView(selection: selection,
                                            board: store.boards[selection.id],
                                            walk: store.walk(for: selection.stop, at: timeline.date),
                                            advice: store.advice(for: selection, at: timeline.date),
                                            loading: store.loadingBoards.contains(selection.id),
                                            failed: store.boardErrors.contains(selection.id),
                                            fresh: store.isBoardFresh(for: selection, at: timeline.date),
                                            fromCurrentLocation: store.location?.isUsable(at: timeline.date) == true,
                                            pinned: store.isPinned(selection), now: timeline.date,
                                            onOpen: { onSelect(selection) },
                                            onPin: { store.togglePin(selection) })
                            }
                        }
                    }
                    if store.selections.count > store.visibleLimit {
                        Button { store.showMore() } label: {
                            Text("More nearby options").frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                    if store.favoritesOnly {
                        Text("Your pinned routes are also available in the Shortcuts app.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if store.canSearchFarther && !store.favoritesOnly {
                    Button {
                        Task { await store.searchFarther() }
                    } label: {
                        Text("Search farther · \(store.radius == 400 ? "800 m" : "1.6 km")").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity, minHeight: 48)
                    .disabled(store.isLoadingStops)
                    .accessibilityIdentifier("search-farther")
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await onRefresh() }
        .navigationTitle("Departs").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMap) {
            if let area = store.area {
                NavigationStack {
                    StopsMapView(userCoordinate: area.coordinate.clLocationCoordinate2D,
                                 stops: store.stops,
                                 stopColors: Dictionary(uniqueKeysWithValues: store.stops.enumerated().map { ($0.element.id, StopPalette.color(at: $0.offset)) }), radius: store.radius)
                    .navigationTitle("Nearby stops").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingMap = false } } }
                }
            }
        }
    }

    private var areaLabel: String {
        guard let area = store.area else { return "Find a departure. Know when to leave." }
        let title = area.source == .chosen ? "Near \(area.name)" : (store.location == nil ? "Last searched area" : "Near you")
        return "\(title) · within \(store.radius < 1000 ? "\(store.radius) m" : "1.6 km")"
    }

    private var statusMessage: String? {
        switch locationState {
        case .requesting: return store.area == nil ? "Finding your location… You can choose an area now." : "Updating your location…"
        case .denied: return "Location is off. Choose an area or use a pinned route."
        case .failed: return "Couldn't find your location. Choose an area to continue."
        default:
            if store.area?.source == .chosen { return "Stops are near your chosen area. Walking advice uses your current location when available." }
            if store.location == nil, store.area != nil { return "Showing your last area while location updates." }
            return nil
        }
    }

    @ViewBuilder private var emptyContent: some View {
        if store.favoritesOnly {
            ContentUnavailableView("Your regular routes, one tap away", systemImage: "pin",
                                   description: Text("Tap the pin on a nearby line to save this stop and direction. No account needed."))
        } else if store.isLoadingStops {
            HStack { ProgressView(); Text("Finding nearby options…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if store.area != nil {
            ContentUnavailableView("No stops in this area", systemImage: "tram",
                                   description: Text("Search farther or choose a different area."))
        } else {
            ContentUnavailableView("Where are you heading from?", systemImage: "location.magnifyingglass",
                                   description: Text("Use your location or search for a stop, address, or place."))
        }
    }
}

private struct RouteFilter: View {
    @Binding var pinned: Bool
    let count: Int

    var body: some View {
        HStack(spacing: 0) {
            segment("Nearby", selected: !pinned) { pinned = false }
            segment("Pinned (\(count))", selected: pinned) { pinned = true }
        }
        .background(Color(.tertiarySystemFill), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route-filter")
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color(.secondarySystemGroupedBackground) : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
