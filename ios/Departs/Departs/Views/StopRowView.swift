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

    private var departures: [Departure] { Array(board?.upcoming(at: now).prefix(2) ?? []) }
    private var answer: String {
        if advice.kind != .unavailable { return advice.kind == .caution ? "Too tight" : advice.title }
        guard let first = departures.first else { return loading ? "Checking…" : "Nothing soon" }
        return fresh ? TimeFormatter.relativeTime(first.time, now: now) ?? TimeFormatter.formatTime(first.time) : TimeFormatter.formatTime(first.time)
    }
    private var times: String {
        departures.map { fresh ? TimeFormatter.relativeTime($0.time, now: now) ?? TimeFormatter.formatTime($0.time) : TimeFormatter.formatTime($0.time) }.joined(separator: " · ")
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
                        if showStop { Text(selection.stop.name).font(.caption) }
                        if !textSize.isAccessibilitySize {
                            Text(status).font(.caption).lineLimit(1)
                        }
                    }
                }
                if !textSize.isAccessibilitySize { Spacer(minLength: 0) }
                VStack(alignment: textSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                    Label(answer, systemImage: advice.kind == .leave ? "checkmark.circle" : advice.kind == .caution ? "exclamationmark.circle" : "clock").font(.headline).monospacedDigit().foregroundStyle(answerColor)
                    Text(times).font(.caption).monospacedDigit()
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(answer). \(selection.line.type.displayName) \(selection.line.name) toward \(selection.line.direction) from \(selection.stop.name). \(times). \(status)")
        .accessibilityValue(selection.id)
        .accessibilityIdentifier("departure-option")
        .swipeActions { pinAction }
        .contextMenu { pinAction }
    }
    private var status: String {
        if failed { return "Couldn't load · retry" }
        if !fresh { return "Saved information" }
        guard let first = departures.first else { return loading ? "Checking departures" : "No upcoming departures" }
        let delay = first.delay.map { Int(ceil($0 / 60)) } ?? 0
        return (first.realTime ? "Live" : "Scheduled") + (delay >= 1 ? " · \(delay) min late" : "")
    }
    private var answerColor: Color {
        switch advice.kind {
        case .leave: Color(hex: scheme == .dark ? "30D158" : "1D7A36")
        case .caution: Color(hex: scheme == .dark ? "FF9F0A" : "B25000")
        case .unavailable: .primary
        }
    }
    private var modeSymbol: String {
        switch selection.line.type {
        case .bus: "bus"
        case .tram: "tram"
        case .subway, .rail: "train.side.front.car"
        }
    }
    private var modeColor: Color {
        switch selection.line.type {
        case .tram: Color(hex: "3A6C9E")
        case .bus: Color(hex: "A8553F")
        case .rail: Color(hex: "3B7A47")
        case .subway: Color(hex: scheme == .dark ? "8065B8" : "6B52A6")
        }
    }
    private var pinAction: some View {
        Button(action: onPin) { Label(pinned ? "Unpin route" : "Pin route", systemImage: pinned ? "pin.slash" : "pin") }
            .accessibilityIdentifier(pinned ? "unpin-route" : "pin-route")
    }
}
