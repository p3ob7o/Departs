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
    /// The shared badge column at standard text sizes. Nil: the badge's own width.
    var badgeWidth: CGFloat? = nil
    var accessibilityID = "departure-option"

    private var content: HomeRowContent { .init(board: board, fresh: fresh, pinned: showStop, now: now) }
    var body: some View {
        Button(action: onOpen) {
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                HStack(alignment: .center, spacing: 8) {
                    LineBadge(line: selection.line).fixedSize()
                        .frame(minWidth: badgeWidth, alignment: .leading)
                        .accessibilityHidden(true)
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
            ? "\(selection.line.type.displayName) \(selection.line.shortName)"
            : String(localized: "\(selection.line.type.displayName) \(selection.line.shortName) toward \(selection.line.direction)")
        return String(localized: "\(service). \(content.spokenAnswer). From \(selection.stop.name).")
    }
    private var pinAction: some View {
        Button(action: onPin) {
            Label(pinned ? String(localized: "Unpin route") : String(localized: "Pin route"), systemImage: pinned ? "pin.slash" : "pin")
        }.accessibilityIdentifier(pinned ? "unpin-route" : "pin-route")
    }
}

struct HomeRowContent {
    /// What the row shows: "7 min", "Now", a clock time, "Nothing soon".
    let answer: String
    /// What VoiceOver says for the same time: "In 7 min" for a countdown.
    let spokenAnswer: String
    let idle: Bool

    init(board: DepartureBoard?, fresh: Bool, pinned: Bool, now: Date) {
        idle = pinned && board != nil && !board!.hasDepartureWithinHorizon
        if idle { answer = String(localized: "Nothing soon"); spokenAnswer = answer }
        else if let board, let departure = fresh ? (board.upcoming(at: now).first ?? board.departures.first) : board.departures.first {
            if fresh, let countdown = TimeFormatter.countdown(departure.time, now: now) {
                answer = countdown.text
                spokenAnswer = countdown.spoken
            } else {
                answer = TimeFormatter.formatTime(departure.time)
                spokenAnswer = answer
            }
        } else { answer = String(localized: "Checking…"); spokenAnswer = answer }
    }
}

/// Destinations start at one x: the badge column is as wide as the widest badge
/// among every listed line, measured from the data rather than from the rows the
/// lazy list happens to have rendered, so nothing shifts while scrolling.
enum BadgeColumn {
    /// One badge per line and mode, pinned rows included. A badge shows only
    /// those two, so directions and stops never change its width.
    static func lines(in selections: [StopLineSelection]) -> [LineInfo] {
        var seen: Set<LineIdentity> = []
        return selections.map(\.line).filter { seen.insert($0.lineIdentity).inserted }
    }

    /// Every badge laid on top of each other: the stack is as wide as the widest.
    struct Stack: View {
        let lines: [LineInfo]
        var body: some View {
            ZStack(alignment: .leading) {
                ForEach(lines, id: \.lineIdentity) { LineBadge(line: $0).fixedSize() }
            }
        }
    }

    /// Measures the stack without drawing it and reports its width.
    struct Reader: View {
        let lines: [LineInfo]
        let onWidth: (CGFloat?) -> Void
        var body: some View {
            Stack(lines: lines)
                .fixedSize()
                .hidden()
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0 > 0 ? $0 : nil) }
        }
    }
}

struct LineBadge: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let line: LineInfo

    var body: some View {
        HStack(spacing: 3) {
            if !textSize.isAccessibilitySize { Image(systemName: line.type.symbol).font(.caption2) }
            Text(line.shortName)
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
