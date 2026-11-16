import SwiftUI

struct StopRowView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let selection: StopLineSelection
    let board: DepartureBoard?
    let fresh: Bool
    let pinned: Bool
    let now: Date
    let onOpen: () -> Void
    let onPin: () -> Void
    var direction: String? = nil
    var showStop = false
    var accessibilityID = "departure-option"

    private var content: HomeRowContent { .init(board: board, fresh: fresh, pinned: showStop, now: now) }
    var body: some View {
        Button(action: onOpen) {
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                HStack(alignment: .center, spacing: 8) {
                    LineBadge(line: selection.line).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(direction ?? selection.line.direction).font(.subheadline)
                            .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if showStop { Text(selection.stop.name).font(.caption) }
                    }
                }
                if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(content.answer).font(.headline).monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .modifier(CountdownTransition(value: content.answer))
            }
            .foregroundStyle(content.idle ? StopPalette.secondaryText : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenAnswer)
        .accessibilityIdentifier(accessibilityID)
        .swipeActions { pinAction }
        .contextMenu { pinAction }
    }
    private var spokenAnswer: String {
        let service = selection.line.direction.isEmpty
            ? "\(selection.line.type.displayName) \(selection.line.name)"
            : String(localized: "\(selection.line.type.displayName) \(selection.line.name) toward \(selection.line.direction)")
        return String(localized: "\(service). \(content.answer). From \(selection.stop.name).")
    }
    private var pinAction: some View {
        Button(action: onPin) {
            Label(pinned ? String(localized: "Unpin route") : String(localized: "Pin route"), systemImage: pinned ? "pin.slash" : "pin")
        }.accessibilityIdentifier(pinned ? "unpin-route" : "pin-route")
    }
}

struct HomeRowContent {
    let answer: String
    let idle: Bool

    init(board: DepartureBoard?, fresh: Bool, pinned: Bool, now: Date) {
        idle = pinned && board != nil && !board!.hasDepartureWithinHorizon
        if idle { answer = String(localized: "Nothing soon") }
        else if let board, let departure = fresh ? (board.upcoming(at: now).first ?? board.departures.first) : board.departures.first {
            answer = fresh ? TimeFormatter.countdown(departure.time, now: now) ?? TimeFormatter.formatTime(departure.time)
                : TimeFormatter.formatTime(departure.time)
        } else { answer = String(localized: "Checking…") }
    }
}

struct LineBadge: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let line: LineInfo

    var body: some View {
        HStack(spacing: 3) {
            if !textSize.isAccessibilitySize { Image(systemName: line.type.symbol).font(.caption2) }
            Text(line.name)
        }
        .font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(StopPalette.modeColor(line.type), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The compact answer and its spoken equivalent share the same selected service.
struct DepartureRowContent {
    struct TimeLabel {
        let text: String
        var tooTight = false
    }
    let answer: String
    let status: String
    let statusSymbol: String
    let adviceKind: DepartureAdvice.Kind
    let times: [TimeLabel]
    var spokenTimes: String {
        times.map { $0.tooTight ? String(localized: "\($0.text), too tight") : $0.text }
            .formatted(.list(type: .and))
    }

    init(board: DepartureBoard?, advice: DepartureAdvice, loading: Bool, failed: Bool, fresh: Bool, idle: Bool, now: Date) {
        let departures = board?.upcoming(at: now) ?? []
        let target = advice.departureTime.flatMap(TimeFormatter.parseISO)
        let showAdvice = !idle && fresh && !failed && advice.kind != .unavailable &&
            (target == nil || target!.timeIntervalSince(now) <= TransitStore.runningHorizon)
        adviceKind = showAdvice ? advice.kind : .unavailable
        func time(_ departure: Departure) -> String {
            fresh && !idle ? TimeFormatter.relativeTime(departure.time, now: now) ?? TimeFormatter.formatTime(departure.time) : TimeFormatter.formatTime(departure.time)
        }
        if let coverage = board?.coverageLimit {
            answer = coverage.message
        } else if showAdvice { answer = advice.kind == .caution ? String(localized: "Too tight") : advice.title }
        else if let first = departures.first { answer = time(first) }
        else if board == nil { answer = loading ? String(localized: "Checking…") : String(localized: "Unavailable") }
        else { answer = failed || !fresh ? String(localized: "Needs an update") : String(localized: "Nothing soon") }

        var shown = Array(departures.prefix(2))
        if showAdvice, let matched = departures.first(where: { $0.time == advice.departureTime }),
           !shown.contains(where: { $0.time == matched.time }), let first = departures.first {
            shown = [first, matched]
        }
        if !showAdvice { shown = Array(shown.dropFirst()) }
        times = shown.map { departure in
            let chosen = showAdvice && departure.time == advice.departureTime
            let tight = showAdvice && advice.isTooTight(departure)
            return .init(text: chosen ? String(localized: "for \(TimeFormatter.formatTime(departure.time))") : time(departure), tooTight: tight)
        }
        if failed {
            status = board == nil ? String(localized: "Couldn't load · retry") : String(localized: "Saved · couldn't update")
            statusSymbol = "exclamationmark.triangle"
        } else if board == nil {
            status = loading ? String(localized: "Checking departures") : String(localized: "Times unavailable")
            statusSymbol = "clock"
        } else if !fresh {
            status = String(localized: "Saved information")
            statusSymbol = "clock.badge.exclamationmark"
        } else if board?.coverageLimit != nil {
            status = String(localized: "Limited timetable")
            statusSymbol = "clock"
        } else if let first = (showAdvice ? departures.first(where: { $0.time == advice.departureTime }) : nil) ?? departures.first {
            let delay = max(0, Int((first.delay ?? 0) / 60))
            if delay >= 1 {
                status = first.realTime ? String(localized: "Live · \(TransitFormat.minutes(delay)) late")
                    : String(localized: "Scheduled · \(TransitFormat.minutes(delay)) late")
            } else {
                status = first.realTime ? String(localized: "Live") : String(localized: "Scheduled")
            }
            statusSymbol = first.realTime ? "dot.radiowaves.left.and.right" : "calendar"
        } else {
            status = String(localized: "No upcoming departures")
            statusSymbol = "clock"
        }
    }
}

struct CountdownTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: String

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: value)
    }
}
