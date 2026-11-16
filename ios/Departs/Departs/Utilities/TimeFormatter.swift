import Foundation

enum TimeFormatter {
    static func countdown(_ time: String, now: Date) -> String? {
        guard let date = parseISO(time) else { return nil }
        let seconds = date.timeIntervalSince(now)
        guard seconds <= TransitStore.runningHorizon else { return nil }
        let duration = Duration.seconds(Int(ceil(seconds / 60)) * 60)
            .formatted(.units(allowed: [.minutes], width: .abbreviated))
        return seconds < 60 ? String(localized: "Now") : String(localized: "In \(duration)")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }

    static func formatTime(_ isoString: String, locale: Locale = .current) -> String {
        guard let date = parseISO(isoString) else { return isoString }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = locale
        formatter.timeZone = timeZone(from: isoString) ?? .current

        return formatter.string(from: date)
    }

    private static func timeZone(from isoString: String) -> TimeZone? {
        if isoString.hasSuffix("Z") {
            return TimeZone(secondsFromGMT: 0)
        }

        guard isoString.count >= 6 else { return nil }

        let suffix = isoString.suffix(6)
        guard suffix.first == "+" || suffix.first == "-" else { return nil }

        let parts = suffix.dropFirst().split(separator: ":")
        guard
            parts.count == 2,
            let hours = Int(parts[0]),
            let minutes = Int(parts[1])
        else {
            return nil
        }

        let sign = suffix.first == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: sign * ((hours * 3600) + (minutes * 60)))
    }
}

/// Keep rounding in the domain rules; Foundation supplies locale-specific units.
enum TransitFormat {
    static func distance(_ meters: Double, locale: Locale = .current) -> String {
        Measurement(value: max(0, meters), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(locale))
    }

    static func minutes(_ minutes: Int, locale: Locale = .current) -> String {
        Duration.seconds(max(0, minutes) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }

    static func walk(_ route: WalkingRoute, fromCurrentLocation: Bool = true) -> String {
        let duration = minutes(max(1, route.walkingMinutes))
        return fromCurrentLocation ? String(localized: "\(duration) walk")
            : String(localized: "\(duration) walk from this area")
    }

}
