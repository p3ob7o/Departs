import SwiftUI
import MapKit

struct DepartureDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selection: StopLineSelection
    @Bindable var store: TransitStore
    @State private var showingMap = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let board = store.boards[selection.id]
            let fresh = store.isBoardFresh(for: selection, at: timeline.date)
            let advice = store.advice(for: selection, at: timeline.date)
            let walk = store.walk(for: selection.stop, at: timeline.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(selection.line.name) → \(selection.line.direction)")
                            .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        Text(selection.stop.name).font(.title3).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(advice.title).font(.title2.bold())
                        Text(advice.detail).font(.subheadline).foregroundStyle(.secondary)
                        if let walk {
                            Label("\(max(1, walk.route.walkingMinutes)) min walk · \(Int(walk.route.distance)) m", systemImage: "figure.walk")
                                .font(.headline)
                            if store.location?.isUsable(at: timeline.date) != true {
                                Text("Walking time is from the searched area, not a confirmed current location.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Next departures").font(.headline)
                            Spacer()
                            if store.loadingBoards.contains(selection.id) { ProgressView().controlSize(.small) }
                            Button { Task { await store.refreshSelection(selection, force: true) } } label: {
                                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                            }.accessibilityLabel("Refresh departures")
                        }
                        if let board {
                            Label { Text(TimeFormatter.freshness(board.checkedAt, now: timeline.date, fresh: fresh)) } icon: {
                                if !fresh { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Color(.label)) }
                            }
                            .font(.caption).foregroundStyle(fresh ? Color.secondary : Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("board-status")
                            let departures = board.upcoming(at: timeline.date)
                            if departures.isEmpty {
                                Text(fresh ? "No upcoming departures found." : "Refresh to see current departure times.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(departures) { departure in
                                let layout = dynamicTypeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                                layout {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(fresh ? (TimeFormatter.relativeTime(departure.time, now: timeline.date) ?? TimeFormatter.formatTime(departure.time)) : TimeFormatter.formatTime(departure.time))
                                            .font(.title2.bold()).monospacedDigit()
                                        if fresh, TimeFormatter.relativeTime(departure.time, now: timeline.date) != nil {
                                            Text(TimeFormatter.formatTime(departure.time)).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                                        Text(departure.realTime ? (fresh ? "Live estimate" : "Saved prediction") : "Scheduled").font(.subheadline)
                                        if let delay = departure.delay, delay >= 60 {
                                            Text("\(Int(ceil(delay / 60))) min late").font(.caption).foregroundStyle(.secondary)
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
                    Button { showingMap.toggle() } label: {
                        Label(showingMap ? "Hide route map" : "Show route map", systemImage: "map")
                            .frame(minHeight: 44)
                    }
                    if showingMap, let origin = store.walkingOrigin {
                        RouteMapView(userCoordinate: origin.clLocationCoordinate2D, stop: selection.stop,
                                     stopColor: StopPalette.colors[0], walkingRoute: walk?.route)
                            .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }.padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await store.refreshSelection(selection, force: true) }
        }
        .navigationTitle(selection.stop.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.togglePin(selection) } label: {
                    Image(systemName: store.isPinned(selection) ? "pin.fill" : "pin").frame(width: 44, height: 44)
                }.accessibilityLabel(store.isPinned(selection) ? "Unpin this direction" : "Pin this direction")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                let destination = MKMapItem(placemark: MKPlacemark(coordinate: selection.stop.location.clLocationCoordinate2D))
                destination.name = selection.stop.name
                destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            } label: {
                Label(dynamicTypeSize.isAccessibilitySize ? "Walk" : "Walking directions", systemImage: "figure.walk")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent).padding(.horizontal, 16).padding(.vertical, 8)
            .background(.bar)
            .accessibilityLabel("Walking directions")
            .accessibilityIdentifier("walking-directions")
        }
        .task(id: selection.id) { await store.refreshSelection(selection) }
    }
}
