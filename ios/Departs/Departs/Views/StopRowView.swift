import SwiftUI

struct StopRowView: View {
    let selection: StopLineSelection
    let board: DepartureBoard?
    let walk: CachedWalk?
    let advice: DepartureAdvice
    let loading: Bool
    let failed: Bool
    let fresh: Bool
    let fromCurrentLocation: Bool
    let pinned: Bool
    let now: Date
    let onOpen: () -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        TransportIconView(type: selection.line.type, color: StopPalette.colors[0])
                            .accessibilityLabel(selection.line.type.displayName)
                        Text("\(selection.line.name) → \(selection.line.direction)")
                            .font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(selection.stop.name).font(.subheadline).foregroundStyle(.secondary)
                    if let board {
                        let departures = Array(board.upcoming(at: now).prefix(2))
                        if departures.isEmpty {
                            Text(fresh ? "No upcoming departures" : "Times need an update")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 18) { times(departures) }
                                VStack(alignment: .leading, spacing: 8) { times(departures) }
                            }
                        }
                        HStack(spacing: 4) {
                            Label { Text(TimeFormatter.freshness(board.checkedAt, now: now, fresh: fresh)) } icon: {
                                if !fresh { Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Color(.label)) }
                            }
                                .fixedSize(horizontal: false, vertical: true)
                            if loading { ProgressView().controlSize(.mini) }
                        }
                        .font(.caption).foregroundStyle(fresh ? Color.secondary : Color.primary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("board-status")
                    } else {
                        HStack {
                            if loading { ProgressView().controlSize(.small) }
                            Text(failed ? "Couldn't load times · tap to retry" : "Checking departures…")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let walk {
                        Label("\(max(1, walk.route.walkingMinutes)) min walk\(fromCurrentLocation ? "" : " from searched area")", systemImage: "figure.walk")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if advice.kind != .unavailable {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(advice.title).font(.headline)
                                .foregroundStyle(.primary)
                            Text(advice.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(advice.title). \(selection.line.type.displayName) \(selection.line.name) toward \(selection.line.direction) from \(selection.stop.name)")
            .accessibilityIdentifier("departure-option")

            Button(action: onPin) {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(pinned ? "Unpin" : "Pin") \(selection.line.name) toward \(selection.line.direction) at \(selection.stop.name)")
            .accessibilityIdentifier(pinned ? "unpin-route" : "pin-route")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func times(_ departures: [Departure]) -> some View {
        ForEach(Array(departures.enumerated()), id: \.element.id) { index, departure in
            VStack(alignment: .leading, spacing: 2) {
                Text(fresh ? (TimeFormatter.relativeTime(departure.time, now: now) ?? TimeFormatter.formatTime(departure.time)) : TimeFormatter.formatTime(departure.time))
                    .font(index == 0 ? .title2.bold() : .headline).monospacedDigit()
                Text("\(index == 0 ? "" : "Then · ")\(departure.realTime ? (fresh ? "Live" : "Saved prediction") : "Scheduled")")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
