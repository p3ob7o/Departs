import MapKit
import SwiftUI

struct DepartureDetailView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var colorScheme
  let selection: StopLineSelection
  @Bindable var store: TransitStore
  var onSelect: (StopLineSelection) -> Void = { _ in }
  @State private var showingMap = false

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
            Text(selection.stop.name).font(.title3)
              .accessibilityIdentifier("detail-stop-name")
          }
          VStack(alignment: .leading, spacing: 8) {
            Label(
              advice.title,
              systemImage: advice.kind == .leave
                ? "checkmark.circle" : advice.kind == .caution ? "exclamationmark.circle" : "clock"
            )
            .font(.title2.bold())
            .foregroundStyle(advice.kind == .leave ? Color(hex: colorScheme == .dark ? "30D158" : "1D7A36") : advice.kind == .caution ? Color(hex: colorScheme == .dark ? "FF9F0A" : "B25000") : Color.primary)
            Text(advice.detail).font(.subheadline).foregroundStyle(.secondary)
            if let walk {
              Label(
                "\(max(1, walk.route.walkingMinutes)) min walk · \(Int(walk.route.distance)) m",
                systemImage: "figure.walk"
              )
              .font(.headline)
              if store.location?.isUsable(at: date) != true {
                Text("Walking time is from the searched area, not a confirmed current location.")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
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
              VStack(alignment: .leading, spacing: 6) {
                if let walk {
                  RoutePreview(coordinates: walk.route.geometry.coordinates)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(height: 44).accessibilityHidden(true)
                }
                Label("Show route map", systemImage: "map")
              }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
                    if fresh, TimeFormatter.relativeTime(departure.time, now: date) != nil
                    {
                      Text(TimeFormatter.formatTime(departure.time)).font(.subheadline)
                        .foregroundStyle(.secondary)
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
                        ? Color(hex: colorScheme == .dark ? "30D158" : "1D7A36") : Color.primary)
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
          if !otherSelections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("Other lines at this stop").font(.headline)
              ForEach(otherSelections) { other in
                Button {
                  onSelect(other)
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text("\(other.line.name) toward \(other.line.direction)")
                    Text(otherTimes(other, at: date)).font(.caption)
                  }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("other-line")
              }
            }
          }
        }.padding(16)
      }
      .background(Color(.systemGroupedBackground))
      .refreshable { await store.refreshSelection(selection, force: true) }
    }
    .navigationTitle("\(selection.line.name) \(selection.line.direction)")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(store.isPinned(selection) ? "Unpin this direction" : "Pin this direction",
               systemImage: store.isPinned(selection) ? "pin.fill" : "pin") {
          store.togglePin(selection)
        }
        .accessibilityIdentifier(store.isPinned(selection) ? "unpin-route" : "pin-route")
      }
    }
    .toolbar {
      ToolbarItem(placement: .bottomBar) {
        Button("Walking directions", systemImage: "figure.walk") {
          let destination = MKMapItem(
            placemark: MKPlacemark(coordinate: selection.stop.location.clLocationCoordinate2D))
          destination.name = selection.stop.name
          destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
          ])
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
      await store.loadGroup(
        .init(id: selection.stop.id, name: selection.stop.name, stops: physicalStops))
    }
  }
  private var physicalStops: [NearbyStop] {
    let nearby = store.stops.filter {
      $0.name == selection.stop.name && $0.location.distance(to: selection.stop.location) <= 150
    }
    return nearby.isEmpty ? [selection.stop] : nearby
  }
  private var otherSelections: [StopLineSelection] {
    physicalStops.flatMap(\.lineSelections).filter {
      $0.id != selection.id
    }
  }
  private func otherTimes(_ other: StopLineSelection, at date: Date) -> String {
    guard let board = store.boards[other.id] else {
      return store.boardErrors.contains(other.id) ? "Couldn't load departures" : "Checking departures…"
    }
    if let coverage = board.coverageLimit { return coverage.message }
    let fresh = store.isBoardFresh(for: other, at: date)
    let times = board.upcoming(at: date).prefix(2).map {
      fresh ? TimeFormatter.relativeTime($0.time, now: date) ?? TimeFormatter.formatTime($0.time) : TimeFormatter.formatTime($0.time)
    }
    return times.isEmpty ? (fresh ? "No upcoming departures" : "Saved information") : times.joined(separator: " · ") + (fresh ? "" : " · Saved information")
  }

}

private struct RoutePreview: Shape {
  let coordinates: [[Double]]
  func path(in rect: CGRect) -> Path {
    let points = coordinates.filter { $0.count >= 2 }.map {
      MKMapPoint(CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]))
    }
    guard let first = points.first else { return Path() }
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    let minX = xs.min() ?? first.x
    let maxX = xs.max() ?? first.x
    let minY = ys.min() ?? first.y
    let maxY = ys.max() ?? first.y
    let bounds = rect.insetBy(dx: 8, dy: 4)
    let scale = min(bounds.width / max(0.000001, maxX - minX), bounds.height / max(0.000001, maxY - minY))
    let origin = CGPoint(x: bounds.midX - (maxX - minX) * scale / 2,
                         y: bounds.midY - (maxY - minY) * scale / 2)
    var path = Path()
    for (index, point) in points.enumerated() {
      let x = origin.x + (point.x - minX) * scale
      let y = origin.y + (point.y - minY) * scale
      if index == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        path.addLine(to: CGPoint(x: x, y: y))
      }
    }
    return path
  }
}
