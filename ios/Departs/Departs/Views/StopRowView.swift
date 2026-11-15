import SwiftUI

struct StopRowView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
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
    var direction: String? = nil
    var showStop = false
    var idle = false

    private var content: DepartureRowContent {
        .init(board: board, advice: advice, loading: loading, failed: failed, fresh: fresh, idle: idle, now: now)
    }
    var body: some View {
        Button(action: onOpen) {
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            layout {
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 3) {
                        if !textSize.isAccessibilitySize { Image(systemName: modeSymbol).font(.caption2) }
                        Text(selection.line.name)
                    }.font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                        .foregroundStyle(.white).background(modeColor, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(direction ?? selection.line.direction).font(.subheadline.weight(.semibold))
                            .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                        if showStop && !textSize.isAccessibilitySize { pinnedDetails }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: content.statusSymbol).font(.caption2)
                            Text(content.status).fixedSize(horizontal: false, vertical: true)
                        }.font(.caption)
                    }
                }
                if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                VStack(alignment: textSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if textSize.isAccessibilitySize {
                            Image(systemName: content.adviceKind == .leave ? "checkmark.circle" : content.adviceKind == .caution ? "exclamationmark.circle" : "clock")
                        }
                        Text(content.answer).fixedSize(horizontal: false, vertical: true)
                    }
                        .font(.headline)
                        .monospacedDigit().foregroundStyle(answerColor)
                    let timesLayout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
                    timesLayout {
                        ForEach(Array(content.times.enumerated()), id: \.offset) { index, time in
                            if index > 0 && !textSize.isAccessibilitySize { Text("·") }
                            Text(time.text).strikethrough(time.tooTight)
                        }
                    }.font(.caption).monospacedDigit()
                }
                if showStop && textSize.isAccessibilitySize { pinnedDetails }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(content.answer). \(selection.line.type.displayName) \(selection.line.name) toward \(selection.line.direction) from \(selection.stop.name). \(content.spokenTimes). \(content.status)\(showStop && walk != nil ? ". \(max(1, walk!.route.walkingMinutes)) min walk" : "")")
        .accessibilityIdentifier("departure-option")
        .swipeActions { pinAction }
        .contextMenu { pinAction }
    }
    private var answerColor: Color {
        switch content.adviceKind {
        case .leave: Color(hex: scheme == .dark ? "30D158" : "1D7A36")
        case .caution: Color(hex: scheme == .dark ? "FF9F0A" : "B25000")
        case .unavailable: .primary
        }
    }
    @ViewBuilder private var pinnedDetails: some View {
        Text(selection.stop.name).font(.caption)
        if let walk {
            Text(fromCurrentLocation ? "\(max(1, walk.route.walkingMinutes)) min walk" : "\(max(1, walk.route.walkingMinutes)) min walk from this area").font(.caption)
        }
    }
    private var modeSymbol: String {
        selection.line.type.symbol
    }
    private var modeColor: Color {
        StopPalette.modeColor(selection.line.type)
    }
    private var pinAction: some View {
        Button(action: onPin) { Label(pinned ? "Unpin route" : "Pin route", systemImage: pinned ? "pin.slash" : "pin") }
            .accessibilityIdentifier(pinned ? "unpin-route" : "pin-route")
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
    var spokenTimes: String { times.map { $0.text + ($0.tooTight ? ", too tight" : "") }.joined(separator: ". ") }

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
        } else if showAdvice { answer = advice.kind == .caution ? "Too tight" : advice.title }
        else if let first = departures.first { answer = time(first) }
        else if board == nil { answer = loading ? "Checking…" : "Unavailable" }
        else { answer = failed || !fresh ? "Needs an update" : "Nothing soon" }

        var shown = Array(departures.prefix(2))
        if showAdvice, let matched = departures.first(where: { $0.time == advice.departureTime }),
           !shown.contains(where: { $0.time == matched.time }), let first = departures.first {
            shown = [first, matched]
        }
        if !showAdvice { shown = Array(shown.dropFirst()) }
        times = shown.map { departure in
            let chosen = showAdvice && departure.time == advice.departureTime
            let tight = showAdvice && ((target.map { (TimeFormatter.parseISO(departure.time) ?? .distantFuture) < $0 }) ?? (advice.kind == .caution))
            return .init(text: chosen ? "for \(TimeFormatter.formatTime(departure.time))" : time(departure), tooTight: tight)
        }
        if failed {
            status = board == nil ? "Couldn't load · retry" : "Saved · couldn't update"
            statusSymbol = "exclamationmark.triangle"
        } else if board == nil {
            status = loading ? "Checking departures" : "Times unavailable"
            statusSymbol = "clock"
        } else if !fresh {
            status = "Saved information"
            statusSymbol = "clock.badge.exclamationmark"
        } else if board?.coverageLimit != nil {
            status = "Limited timetable"
            statusSymbol = "clock"
        } else if let first = (showAdvice ? departures.first(where: { $0.time == advice.departureTime }) : nil) ?? departures.first {
            let delay = max(0, Int((first.delay ?? 0) / 60))
            status = (first.realTime ? "Live" : "Scheduled") + (delay >= 1 ? " · \(delay) min late" : "")
            statusSymbol = first.realTime ? "dot.radiowaves.left.and.right" : "calendar"
        } else {
            status = "No upcoming departures"
            statusSymbol = "clock"
        }
    }
}
