import Foundation

enum TimeFormatter {
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

    /// Returns relative time string for departures within 30 minutes, nil otherwise.
    static func relativeTime(_ isoString: String) -> String? {
        guard let date = parseISO(isoString) else { return nil }
        let minutes = Int(date.timeIntervalSinceNow / 60)
        if minutes <= 0 {
            return "Now"
        } else if minutes <= 30 {
            return "in \(minutes) min"
        }
        return nil
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
