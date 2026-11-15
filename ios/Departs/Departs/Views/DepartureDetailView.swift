import MapKit
import SwiftUI

struct DepartureDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let selection: StopLineSelection
    @Bindable var store: TransitStore
    var onSelect: (StopLineSelection) -> Void = { _ in }
    @State private var showingMap = false
    @State private var showingIdle = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let date = max(timeline.date, Date.now)
            let board = store.boards[selection.id]
            let fresh = store.isBoardFresh(for: selection, at: date)
            let advice = store.advice(for: selection, at: date)
            let walk = store.walk(for: selection.stop, at: date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        LineBadge(line: selection.line)
                            .accessibilityLabel("\(selection.line.type.displayName) \(selection.line.name)")
                        Text(selection.line.direction).font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("detail-direction")
                        Text(selection.stop.name).font(.title3)
                            .accessibilityIdentifier("detail-stop-name")
                        if let walk {
                            Label(
                                "\(max(1, walk.route.walkingMinutes)) min walk · \(Int(walk.route.distance)) m",
                                systemImage: "figure.walk"
                            )
                            .font(.subheadline)
                            if store.location?.isUsable(at: date) != true {
                                Text("Walking time is from the searched area, not a confirmed current location.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            advice.title,
                            systemImage: advice.kind == .leave
                                ? "checkmark.circle" : advice.kind == .caution ? "exclamationmark.circle" : "clock"
                        )
                        .font(.title2.bold())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("departure-advice-title")
                        .foregroundStyle(
                            advice.kind == .leave
                                ? Color(hex: colorScheme == .dark ? "30D158" : "1D7A36")
                                : advice.kind == .caution
                                    ? Color(hex: colorScheme == .dark ? "FF9F0A" : "B25000") : Color.primary)
                        Text(advice.detail).font(.subheadline).foregroundStyle(.secondary)
                        if !fresh {
                            Button {
                                Task { await store.refreshSelection(selection, force: true) }
                            } label: {
                                Label("Refresh now", systemImage: "arrow.clockwise").frame(minHeight: 44)
                            }.accessibilityIdentifier("refresh-advice")
                        }
                        Button {
                            showingMap = true
                        } label: {
                            Label("Show route map", systemImage: "map")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("show-route-map")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(
                        Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Next departures").font(.headline)
                            Spacer()
                            if store.loadingBoards.contains(selection.id) { ProgressView().controlSize(.small) }
                            Button {
                                Task { await store.refreshSelection(selection, force: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                            }.accessibilityLabel("Refresh departures")
                        }
                        if let board {
                            Label {
                                Text(TimeFormatter.freshness(board.checkedAt, now: date, fresh: fresh))
                            } icon: {
                                if !fresh {
                                    Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Color(.label))
                                }
                            }
                            .font(.caption).foregroundStyle(fresh ? Color.secondary : Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("board-status")
                            let departures = board.upcoming(at: date)
                            if departures.isEmpty && board.coverageLimit == nil {
                                Text(
                                    fresh
                                        ? "No upcoming departures found." : "Refresh to see current departure times."
                                )
                                .foregroundStyle(.secondary)
                            }
                            ForEach(departures) { departure in
                                let tooTight = advice.isTooTight(departure)
                                let layout =
                                    dynamicTypeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                                layout {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(
                                            fresh
                                                ? (TimeFormatter.relativeTime(departure.time, now: date)
                                                    ?? TimeFormatter.formatTime(departure.time))
                                                : TimeFormatter.formatTime(departure.time)
                                        )
                                        .font(.title2.bold()).monospacedDigit()
                                        .strikethrough(tooTight)
                                        if fresh, TimeFormatter.relativeTime(departure.time, now: date) != nil {
                                            Text(TimeFormatter.formatTime(departure.time)).font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        if tooTight {
                                            Text("Too tight to catch").font(.subheadline)
                                                .accessibilityIdentifier("departure-too-tight")
                                        }
                                    }
                                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                    VStack(
                                        alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing,
                                        spacing: 3
                                    ) {
                                        Label(
                                            departure.realTime
                                                ? (fresh ? "Live estimate" : "Saved prediction") : "Scheduled",
                                            systemImage: fresh && departure.realTime
                                                ? "dot.radiowaves.left.and.right" : "clock"
                                        )
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            fresh && departure.realTime
                                                ? Color(hex: colorScheme == .dark ? "30D158" : "1D7A36") : Color.primary
                                        )
                                        if let delay = departure.delay, delay >= 60 {
                                            Label(
                                                "\(Int(delay / 60)) min late", systemImage: "exclamationmark.circle"
                                            )
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color(hex: colorScheme == .dark ? "FF9F0A" : "B25000"))
                                        }
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }.padding(.vertical, 8)
                                Divider()
                            }
                        } else if store.boardErrors.contains(selection.id) {
                            Text("Couldn't load departure times. Try refreshing.").foregroundStyle(.secondary)
                        } else {
                            Text("Checking departures…").foregroundStyle(.secondary)
                        }
                    }
                    let group = store.group(containing: selection.stop)
                    let active = group.active.filter { $0.id != selection.id }
                    let idle = group.idle.filter { $0.id != selection.id }
                    if !active.isEmpty || !idle.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Other lines at this stop").font(.headline)
                            ForEach(active) { other in
                                otherRow(other, at: date)
                                Divider()
                            }
                            if !idle.isEmpty {
                                DisclosureGroup(isExpanded: $showingIdle) {
                                    ForEach(idle) { other in
                                        otherRow(other, at: date, idle: true).padding(.vertical, 6)
                                    }
                                } label: {
                                    Text(
                                        idle.contains { store.boards[$0.id]?.coverageLimit != nil }
                                            ? "\(idle.count) more lines" : "\(idle.count) lines with nothing soon"
                                    )
                                    .font(.subheadline).frame(minHeight: 44)
                                }.accessibilityIdentifier("other-lines-idle")
                            }
                        }
                    }
                }.padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .onScrollPhaseChange { _, phase in store.interacting = phase != .idle }
            .refreshable { await store.refreshSelection(selection, force: true) }
        }
        .navigationTitle("\(selection.line.name) \(selection.line.direction)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    store.isPinned(selection) ? "Unpin this direction" : "Pin this direction",
                    systemImage: store.isPinned(selection) ? "pin.fill" : "pin"
                ) {
                    store.togglePin(selection)
                }
                .accessibilityIdentifier(store.isPinned(selection) ? "unpin-route" : "pin-route")
            }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    let destination = MKMapItem(
                        placemark: MKPlacemark(coordinate: selection.stop.location.clLocationCoordinate2D))
                    destination.name = selection.stop.name
                    destination.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                    ])
                } label: {
                    HStack {
                        Image(systemName: "figure.walk")
                        Text("Walking directions")
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityShowsLargeContentViewer {
                        Label("Walking directions", systemImage: "figure.walk")
                    }
                }
                .accessibilityLabel("Walking directions")
                .accessibilityIdentifier("walking-directions")
            }
        }
        .sheet(isPresented: $showingMap) {
            NavigationStack {
                RouteMapView(
                    userCoordinate: (store.walkingOrigin ?? selection.stop.location).clLocationCoordinate2D,
                    stop: selection.stop, stopColor: StopPalette.modeColor(selection.line.type),
                    walkingRoute: store.walk(for: selection.stop)?.route, line: selection.line
                )
                .navigationTitle("Walking route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done", systemImage: "checkmark") { showingMap = false } }
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        }
        .task(id: selection.id) {
            await store.refreshSelection(selection)
            await store.loadGroup(store.group(containing: selection.stop))
        }
        .onChange(of: selection.id) { _, _ in showingIdle = false }
        .onDisappear { store.interacting = false }
    }
    private func otherRow(_ other: StopLineSelection, at date: Date, idle: Bool = false) -> some View {
        StopRowView(
            selection: other, board: store.boards[other.id], walk: store.walk(for: other.stop, at: date),
            advice: store.advice(for: other, at: date), loading: store.loadingBoards.contains(other.id),
            failed: store.boardErrors.contains(other.id), fresh: store.isBoardFresh(for: other, at: date),
            fromCurrentLocation: store.location?.isUsable(at: date) == true, pinned: store.isPinned(other), now: date,
            onOpen: { onSelect(other) }, onPin: { store.togglePin(other) }, idle: idle, accessibilityID: "other-line")
    }
}
