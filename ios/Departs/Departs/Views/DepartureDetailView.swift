import MapKit
import SwiftUI

struct DepartureDetailView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let selection: StopLineSelection
    @Bindable var store: TransitStore
    @State private var countdownStart = Date.now

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: countdownStart, by: 15)) { timeline in
                let date = max(timeline.date, Date.now)
                let board = store.boards[selection.id]
                let fresh = store.isBoardFresh(for: selection, at: date)
                let walk = store.walk(for: selection.stop, at: date)
                VStack(spacing: 0) {
                    if !textSize.isAccessibilitySize { map(width: geometry.size.width, walk: walk, at: date) }
                    List {
                        if textSize.isAccessibilitySize {
                            map(width: geometry.size.width, walk: walk, at: date)
                                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                        }
                        heading(walk: walk, at: date)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.vertical, 8)
                        if let board {
                            if !fresh { refreshButton(savedAt: board.checkedAt) }
                            let departures = board.upcoming(at: board.checkedAt)
                            if !board.hasDepartureWithinHorizon {
                                Text("Nothing in the next hour").accessibilityIdentifier("line-empty")
                            }
                            ForEach(Array(departures.prefix(4))) { departure in
                                departureRow(departure, fresh: fresh, at: date)
                                    .listRowInsets(.vertical, 0)
                            }
                        } else if store.boardErrors.contains(selection.id) {
                            refreshButton(savedAt: nil)
                        } else {
                            Label("Checking departures…", systemImage: "clock")
                                .accessibilityIdentifier("board-status")
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 0)
                    .contentMargins(.top, 0, for: .scrollContent)
                    .accessibilityIdentifier("departure-detail")
                    .refreshable { await store.refreshSelection(selection, force: true) }
                }
            }
        }
        .navigationTitle("\(selection.line.name) \(selection.line.direction)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Walking directions", systemImage: "figure.walk") {
                    WalkingDirections.destination(for: selection).openInMaps(
                        launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                }.accessibilityIdentifier("walking-directions")
                Button(store.isPinned(selection) ? String(localized: "Unpin this direction") : String(localized: "Pin this direction"),
                       systemImage: store.isPinned(selection) ? "pin.fill" : "pin") {
                    store.togglePin(selection)
                }.accessibilityIdentifier(store.isPinned(selection) ? "unpin-route" : "pin-route")
            }
        }
        .task(id: selection.id) { await store.refreshSelection(selection) }
    }

    private func map(width: CGFloat, walk: CachedWalk?, at date: Date) -> some View {
        RouteMapView(userCoordinate: store.walkingOrigin?.clLocationCoordinate2D,
                     stop: selection.stop, stopColor: StopPalette.modeColor(selection.line.type),
                     walkingRoute: walk?.route, line: selection.line,
                     originIsCurrentLocation: store.location?.isUsable(at: date) == true)
            .frame(width: width, height: width)
            .accessibilityIdentifier("line-map")
    }

    private func heading(walk: CachedWalk?, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // The system title can truncate a long headsign and does not grow
            // with Dynamic Type. Keep the full service visible in the content.
            Text("\(selection.line.name) \(selection.line.direction)").font(.headline)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("detail-direction")
            Text(stopSummary(walk: walk, at: date)).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("detail-stop-name")
        }.foregroundStyle(Color.primary)
    }

    private func stopSummary(walk: CachedWalk?, at date: Date) -> String {
        let current = store.location?.isUsable(at: date) == true
        if let walk {
            return String(localized: "\(selection.stop.name) · \(TransitFormat.walk(walk.route, fromCurrentLocation: current)) · \(TransitFormat.distance(walk.route.distance))")
        }
        // No origin at all: a pinned route opened while location is off.
        return current || store.walkingOrigin == nil ? selection.stop.name
            : String(localized: "\(selection.stop.name) · from this area")
    }

    private func refreshButton(savedAt: Date?) -> some View {
        Button { Task { await store.refreshSelection(selection, force: true) } } label: {
            if let savedAt {
                Label("Saved times from \(savedAt.formatted(date: .omitted, time: .shortened)) · Refresh", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            } else {
                Label("Couldn't load · Retry", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }
        }.foregroundStyle(.tint).accessibilityIdentifier("refresh-line")
    }

    private func departureRow(_ departure: Departure, fresh: Bool, at date: Date) -> some View {
        let content = LineDepartureContent(departure: departure, fresh: fresh, now: date)
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(content.countdown ?? content.clock).font(.headline).monospacedDigit()
                .modifier(CountdownTransition(value: content.countdown ?? content.clock))
            if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
            if content.live {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right").accessibilityHidden(true)
                    if let delay = content.delay { Text(delay) }
                }.font(.subheadline)
            }
            if content.countdown != nil { Text(content.clock).font(.subheadline).monospacedDigit() }
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spoken)
        .accessibilityIdentifier("line-departure")
    }
}

struct LineDepartureContent {
    let countdown: String?
    let clock: String
    let live: Bool
    let delay: String?
    var spoken: String {
        var parts = countdown.map { [$0, clock] } ?? [clock]
        if live { parts.append(String(localized: "Live departure")) }
        if let delay { parts.append(delay) }
        return parts.joined(separator: ". ")
    }

    init(departure: Departure, fresh: Bool, now: Date) {
        countdown = fresh ? TimeFormatter.countdown(departure.time, now: now) : nil
        clock = TimeFormatter.formatTime(departure.time)
        live = fresh && departure.realTime
        let delayMinutes = Int(max(0, departure.delay ?? 0) / 60)
        delay = live && delayMinutes >= 1 ? String(localized: "\(TransitFormat.minutes(delayMinutes)) late") : nil
    }
}

enum WalkingDirections {
    static func destination(for selection: StopLineSelection) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: selection.stop.location.lat, longitude: selection.stop.location.lon), address: nil)
        item.name = selection.stop.name
        return item
    }
}
