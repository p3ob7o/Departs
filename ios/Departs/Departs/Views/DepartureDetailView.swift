import MapKit
import SwiftUI

struct DepartureDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let selection: StopLineSelection
    @Bindable var store: TransitStore
    var onSelect: (StopLineSelection) -> Void = { _ in }
    var onMap: () -> Void = {}
    var interactionID = "detail"
    @Binding var scrollTarget: String?
    @State private var showingIdle = false
    @State private var countdownStart = Date.now

    var body: some View {
        TimelineView(.periodic(from: countdownStart, by: 15)) { timeline in
            let date = max(timeline.date, Date.now)
            let board = store.boards[selection.id]
            let fresh = store.isBoardFresh(for: selection, at: date)
            let advice = store.advice(for: selection, at: date)
            let walk = store.walk(for: selection.stop, at: date)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
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
                                "\(TransitFormat.walk(walk.route)) · \(TransitFormat.distance(walk.route.distance))",
                                systemImage: "figure.walk"
                            )
                            .font(.subheadline)
                            if store.location?.isUsable(at: date) != true {
                                Text("Walking time is from the searched area, not a confirmed current location.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.id("header")
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            advice.title,
                            systemImage: advice.kind == .leave
                                ? "checkmark.circle" : advice.kind == .caution ? "exclamationmark.circle" : "clock"
                        )
                        .font(.title2.bold())
                        .modifier(CountdownTransition(value: advice.title))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("departure-advice-title")
                        .foregroundStyle(
                            advice.kind == .leave
                                ? Color(hex: colorScheme == .dark ? "30D158" : "1D7A36")
                                : advice.kind == .caution
                                    ? Color(hex: colorScheme == .dark ? "FF9F0A" : "B25000") : Color.primary)
                        Text(advice.detail).font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("departure-advice-detail")
                        if !fresh {
                            Button {
                                Task { await store.refreshSelection(selection, force: true) }
                            } label: {
                                Label("Refresh now", systemImage: "arrow.clockwise").frame(minHeight: 44)
                            }.accessibilityIdentifier("refresh-advice")
                        }
                        Button(action: onMap) {
                            Label("Show route map", systemImage: "map")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("show-route-map")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(
                        Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    .id("advice")

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
                                        ? String(localized: "No upcoming departures found.") : String(localized: "Refresh to see current departure times.")
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
                                        .modifier(CountdownTransition(value: TimeFormatter.relativeTime(departure.time, now: date) ?? departure.time))
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
                                                ? (fresh ? String(localized: "Live departure") : String(localized: "Last known departure")) : String(localized: "Scheduled"),
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
                                                "\(TransitFormat.minutes(Int(delay / 60))) late", systemImage: "exclamationmark.circle"
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
                    }.id("departures")
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
                                        TransitFormat.idleLines(idle.count, limited: idle.contains { store.boards[$0.id]?.coverageLimit != nil })
                                    )
                                    .font(.subheadline).frame(minHeight: 44)
                                }.accessibilityIdentifier("other-lines-idle")
                            }
                        }.id("other")
                    }
                }
                .scrollTargetLayout()
                .padding(16).frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $scrollTarget)
            .accessibilityIdentifier("departure-detail")
            .background(Color(.systemGroupedBackground))
            .onScrollPhaseChange { _, phase in store.setInteracting(phase != .idle, presentationID: interactionID) }
            .refreshable { await store.refreshSelection(selection, force: true) }
        }
        .navigationTitle("\(selection.line.name) \(selection.line.direction)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    store.isPinned(selection) ? String(localized: "Unpin this direction") : String(localized: "Pin this direction"),
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
        .task(id: selection.id) {
            await store.refreshSelection(selection)
        }
        .onChange(of: selection.id) { _, _ in
            showingIdle = false
            scrollTarget = "header"
        }
        .onDisappear { store.clearPresentation(interactionID) }
    }
    private func otherRow(_ other: StopLineSelection, at date: Date, idle: Bool = false) -> some View {
        StopRowView(
            selection: other, board: store.boards[other.id], fresh: store.isBoardFresh(for: other, at: date),
            pinned: store.isPinned(other), now: date,
            onOpen: { onSelect(other) }, onPin: { store.togglePin(other) }, accessibilityID: "other-line")
    }
}
