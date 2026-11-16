import Foundation

struct LocationFix {
    let coordinate: Coordinate
    let capturedAt: Date
    let accuracy: Double

    func isUsable(at now: Date) -> Bool {
        coordinate.isValid && accuracy >= 0 && accuracy <= 100 && capturedAt.isRecent(at: now, within: 120)
    }
}

struct DepartureBoard: Codable {
    let departures: [Departure]
    let checkedAt: Date

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

/// The last place the rider was, and the stops within reach of it.
struct NearbySnapshot: Codable {
    let center: Coordinate
    let stops: [NearbyStop]
    let checkedAt: Date
}

/// A published home list includes its boards, so membership, order and times
/// cannot get out of step while an incoming refresh waits for a scroll to end.
struct HomeSnapshot: Codable {
    var groups: [HomeStopGroup] = []
    var pins: [StopLineSelection] = []
    var boards: [String: DepartureBoard] = [:]
    var missing: Set<String> = []
    var checkedAt: Date?

    var selections: [StopLineSelection] { pins + groups.flatMap(\.active) }

    static func physicalStops(_ stops: [NearbyStop], from origin: Coordinate) -> [HomeStopGroup] {
        var groups: [HomeStopGroup] = []
        for stop in stops {
            if let index = groups.firstIndex(where: {
                $0.name == stop.name && $0.stops[0].location.distance(to: stop.location) <= 150
            }) {
                groups[index].stops.append(stop)
            } else {
                groups.append(.init(id: stop.id, name: stop.name, stops: [stop]))
            }
        }
        // A total ordering; walking routes never participate in selection.
        return groups.enumerated().sorted {
            let a = $0.element.distance(from: origin), b = $1.element.distance(from: origin)
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }

    static func make(stops: [NearbyStop], origin: Coordinate, pins: [StopLineSelection],
                     response: BatchDepartures, checkedAt: Date) -> HomeSnapshot {
        let received = Dictionary(response.boards.map { ($0.stopId, $0) }, uniquingKeysWith: { first, _ in first })
        let missing = Set(stops.map(\.id)).subtracting(received.keys).union(response.missing)
        let localIDs = Set(stops.map(\.id))
        var pinnedIdentities: Set<ServiceIdentity> = []
        let nearbyPins = pins.filter { localIDs.contains($0.stop.id) && pinnedIdentities.insert($0.line.serviceIdentity).inserted }
        let pinnedServices = Set(nearbyPins.map { $0.line.serviceIdentity })
        var result = HomeSnapshot(pins: nearbyPins, missing: missing, checkedAt: checkedAt)
        var chosen: [LineIdentity: Set<String>] = [:]
        var usedSecondStop: Set<LineIdentity> = []
        for var group in physicalStops(stops, from: origin) {
            var candidates: [StopLineSelection] = []
            var candidateIndex: [ServiceIdentity: Int] = [:]
            // Retain provider order, choosing the nearest eligible platform
            // when the same destination is returned by two platforms here.
            for stop in group.stops {
                for (index, item) in (received[stop.id]?.groups ?? []).enumerated() {
                    let selection = StopLineSelection(stop: stop, line: item.line, lineIndex: index)
                    let board = DepartureBoard(departures: item.departures, checkedAt: checkedAt)
                    result.boards[selection.id] = board
                    guard board.hasDepartureWithinHorizon else { continue }
                    if let previous = candidateIndex[item.line.serviceIdentity] {
                        if stop.location.distance(to: origin) < candidates[previous].stop.location.distance(to: origin) {
                            candidates[previous] = selection
                        }
                    } else {
                        candidateIndex[item.line.serviceIdentity] = candidates.count
                        candidates.append(selection)
                    }
                }
            }
            let firstDestinations = Dictionary(grouping: candidates, by: { $0.line.lineIdentity })
                .mapValues { Set($0.map { $0.line.direction }) }
            let nearestLines = Set(firstDestinations.keys).subtracting(chosen.keys)
            for candidate in candidates {
                let line = candidate.line.lineIdentity
                if !nearestLines.contains(line), let earlier = chosen[line] {
                    guard earlier.count == 1, !usedSecondStop.contains(line),
                          !earlier.contains(candidate.line.direction) else { continue }
                    usedSecondStop.insert(line)
                    chosen[line, default: []].insert(candidate.line.direction)
                }
                if !pinnedServices.contains(candidate.line.serviceIdentity) { group.active.append(candidate) }
            }
            // Pins count toward the nearest stop's destinations too; hiding a
            // duplicate must not promote a third destination at a farther stop.
            for line in nearestLines { chosen[line] = firstDestinations[line] }
            group.hasMissingBoard = group.stops.contains { missing.contains($0.id) }
            if !group.active.isEmpty || group.hasMissingBoard { result.groups.append(group) }
        }
        for pin in nearbyPins where !missing.contains(pin.stop.id) && result.boards[pin.id] == nil {
            result.boards[pin.id] = .init(departures: [], checkedAt: checkedAt)
        }
        return result
    }
}

struct HomeStopGroup: Codable, Identifiable {
    let id: String
    let name: String
    var stops: [NearbyStop]
    var active: [StopLineSelection] = []
    var hasMissingBoard = false
    var coordinate: Coordinate {
        let count = Double(max(1, stops.count))
        return .init(lat: stops.reduce(0) { $0 + $1.location.lat } / count,
                     lon: stops.reduce(0) { $0 + $1.location.lon } / count)
    }
    var lines: [LineInfo] {
        var seen: Set<LineIdentity> = []
        return active.map(\.line).filter { seen.insert($0.lineIdentity).inserted }
    }
    func nearestPlatform(to origin: Coordinate) -> NearbyStop? {
        stops.min { $0.location.distance(to: origin) < $1.location.distance(to: origin) }
    }
    func distance(from origin: Coordinate) -> Double {
        nearestPlatform(to: origin)?.location.distance(to: origin) ?? .infinity
    }
}

struct LineIdentity: Hashable {
    let mode: TransportType
    let name: String
}

struct ServiceIdentity: Hashable {
    let line: LineIdentity
    let direction: String
}

extension LineInfo {
    var lineIdentity: LineIdentity { .init(mode: type, name: name) }
    var serviceIdentity: ServiceIdentity { .init(line: lineIdentity, direction: direction) }
}

extension DepartureBoard {
    var hasDepartureWithinHorizon: Bool {
        upcoming(at: checkedAt).contains {
            (TimeFormatter.parseISO($0.time)?.timeIntervalSince(checkedAt) ?? .infinity) <= TransitStore.runningHorizon
        }
    }
}

extension Date {
    func isRecent(at now: Date, within interval: TimeInterval) -> Bool {
        let age = now.timeIntervalSince(self)
        return age >= -5 && age <= interval
    }
}
