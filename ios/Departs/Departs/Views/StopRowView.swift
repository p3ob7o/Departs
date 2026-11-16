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

struct CountdownTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: String

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: value)
    }
}
