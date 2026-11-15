import Foundation

struct SearchArea: Codable, Equatable {
    enum Source: String, Codable { case location, chosen }
    let coordinate: Coordinate
    let name: String
    let source: Source
}

struct LocationFix {
    let coordinate: Coordinate
    let capturedAt: Date
    let accuracy: Double

    func isUsable(at now: Date) -> Bool {
        coordinate.isValid && accuracy >= 0 && accuracy <= 100 && capturedAt.isRecent(at: now, within: 120)
    }
}

struct DepartureBoard: Codable {
    struct CoverageLimit: Codable {
        /// Latest time represented by an incomplete provider response. It is
        /// evidence about the returned board, not a guarantee of live coverage.
        let before: String?
        var message: String {
            before.map { "No departure listed before \(TimeFormatter.formatTime($0))" } ?? "Later departures aren't listed"
        }
    }
    let departures: [Departure]
    let checkedAt: Date
    var coverageLimit: CoverageLimit? = nil

    func isFresh(at now: Date) -> Bool { checkedAt.isRecent(at: now, within: 60) }

    func upcoming(at now: Date) -> [Departure] {
        departures.compactMap { departure -> (Departure, Date)? in
            guard let date = TimeFormatter.parseISO(departure.time), date >= now else { return nil }
            return (departure, date)
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

struct CachedWalk: Codable {
    let origin: Coordinate
    let route: WalkingRoute
    let checkedAt: Date

    func matches(_ coordinate: Coordinate, at now: Date) -> Bool {
        checkedAt.isRecent(at: now, within: 600) && origin.distance(to: coordinate) <= 40
    }
}

struct NearbySnapshot: Codable {
    let area: SearchArea
    let radius: Int
    let stops: [NearbyStop]
    let checkedAt: Date
}

struct DepartureAdvice: Equatable {
    enum Kind { case leave, caution, unavailable }
    let title: String
    let detail: String
    let kind: Kind
    var departureTime: String? = nil

    static let buffer: TimeInterval = 120

    func isTooTight(_ departure: Departure) -> Bool {
        guard kind != .unavailable else { return false }
        if kind == .caution { return true }
        guard let target = departureTime.flatMap(TimeFormatter.parseISO),
              let time = TimeFormatter.parseISO(departure.time) else { return false }
        return time < target
    }

    static func make(board: DepartureBoard?, walk: CachedWalk?, location: LocationFix?,
                     requestFailed: Bool = false, now: Date = .now) -> DepartureAdvice {
        guard let board, board.isFresh(at: now), !requestFailed else {
            return .init(title: "Refresh before you leave", detail: "Departure times need an update", kind: .unavailable)
        }
        if let coverage = board.coverageLimit {
            return .init(title: coverage.message, detail: "Later times aren't listed in this timetable", kind: .unavailable)
        }
        let departures = board.upcoming(at: now)
        guard !departures.isEmpty else {
            return .init(title: "No upcoming departures", detail: "Try another line or search farther", kind: .unavailable)
        }
        guard let location, location.isUsable(at: now) else {
            return .init(title: "Check your walking time", detail: "A recent, precise location is needed for leave-time advice", kind: .unavailable)
        }
        guard let walk, walk.matches(location.coordinate, at: now), walk.route.duration.isFinite, walk.route.duration >= 0 else {
            return .init(title: "Check your walking time", detail: "Open walking directions to plan your arrival", kind: .unavailable)
        }
        let required = walk.route.duration + buffer
        guard let departure = departures.first(where: {
            (TimeFormatter.parseISO($0.time)?.timeIntervalSince(now) ?? -.infinity) >= required
        }), let time = TimeFormatter.parseISO(departure.time) else {
            return .init(title: "These departures look too tight", detail: "Allow \(max(1, walk.route.walkingMinutes)) min walking + 2 min buffer", kind: .caution)
        }
        let leaveIn = max(0, Int(floor((time.timeIntervalSince(now) - required) / 60)))
        let title = leaveIn == 0 ? "Leave now" : "Leave in \(leaveIn) min"
        let skipped = departure.id != departures.first?.id
        let service = departure.realTime ? "Live estimate" : "Scheduled estimate"
        return .init(title: title,
                     detail: "\(skipped ? "Earlier departure is tight · " : "")\(TimeFormatter.formatTime(departure.time)) · \(service.lowercased()) · 2 min buffer",
                     kind: .leave, departureTime: departure.time)
    }
}

extension Date {
    func isRecent(at now: Date, within interval: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(self)
        return age >= -5 && age <= interval
    }
}
