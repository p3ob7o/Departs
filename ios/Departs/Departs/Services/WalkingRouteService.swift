import MapKit
import os

@MainActor
final class WalkingRouteService {
    static let shared = WalkingRouteService()

    private struct Endpoints: Hashable {
        let origin: Coordinate
        let destination: Coordinate
    }

    typealias RouteData = (polyline: MKPolyline, duration: TimeInterval, distance: CLLocationDistance)
    typealias Completion = (Result<RouteData, Error>) -> Void
    typealias Start = (MKDirections.Request, @escaping Completion) -> () -> Void

    private final class Ticket: Sendable {
        private let cancelled = OSAllocatedUnfairLock(initialState: false)
        var isCancelled: Bool { cancelled.withLock { $0 } }
        func cancel() { cancelled.withLock { $0 = true } }
    }

    private struct Request {
        let id = UUID()
        var waiters: [UUID: (Ticket, CheckedContinuation<WalkingRoute, Error>)] = [:]
        var cancel: (() -> Void)?
        var timeout: Task<Void, Never>?
    }

    static let cacheCapacity = 32
    private static let concurrencyLimit = 3
    private static let timeout: Duration = .seconds(12)

    private let start: Start
    private let now: () -> Date
    private let sleep: (Duration) async throws -> Void
    private var routes: [Endpoints: (route: WalkingRoute, expiresAt: Date, insertion: UInt64)] = [:]
    private var insertion: UInt64 = 0
    private var priorityDestinations: Set<Coordinate> = []
    private var requests: [Endpoints: Request] = [:]
    private var queue: [Endpoints] = []
    private var active = 0

    init(now: @escaping () -> Date = { .now },
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         start: Start? = nil) {
        self.now = now
        self.sleep = sleep
        self.start = start ?? Self.startWalkingRoute
    }

    func prioritize(destinations: Set<Coordinate>) {
        priorityDestinations = destinations
    }

    func route(from origin: Coordinate, to destination: Coordinate) async throws -> WalkingRoute {
        try Task.checkCancellation()
        let endpoints = Endpoints(origin: origin, destination: destination)
        let ticket = Ticket()
        let waiterID = UUID()
        let route = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WalkingRoute, Error>) in
                // A replacement can arrive before the cancelled caller's MainActor cleanup.
                removeCancelledWaiters()
                routes = routes.filter { $0.value.expiresAt > now() }
                if ticket.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if let entry = routes[endpoints] {
                    continuation.resume(returning: entry.route)
                } else {
                    if requests[endpoints] == nil {
                        requests[endpoints] = Request()
                        queue.append(endpoints)
                    }
                    requests[endpoints]?.waiters[waiterID] = (ticket, continuation)
                }
                startQueuedRequests()
            }
        } onCancel: {
            ticket.cancel()
            Task { @MainActor in
                self.removeCancelledWaiters()
                self.startQueuedRequests()
            }
        }
        try Task.checkCancellation()
        return route
    }

    private func removeCancelledWaiters() {
        for endpoints in Array(requests.keys) {
            guard var request = requests[endpoints] else { continue }
            for (id, (ticket, waiter)) in request.waiters where ticket.isCancelled {
                request.waiters[id] = nil
                waiter.resume(throwing: CancellationError())
            }
            if request.waiters.isEmpty {
                removeRequest(at: endpoints, request: request, cancel: true)
            } else {
                requests[endpoints] = request
            }
        }
    }

    private func startQueuedRequests() {
        while active < Self.concurrencyLimit, !queue.isEmpty {
            let index = queue.firstIndex { priorityDestinations.contains($0.destination) } ?? queue.startIndex
            let endpoints = queue.remove(at: index)
            guard let id = requests[endpoints]?.id else { continue }
            let request = MKDirections.Request()
            request.source = Self.mapItem(at: endpoints.origin)
            request.destination = Self.mapItem(at: endpoints.destination)
            request.transportType = .walking
            request.requestsAlternateRoutes = false

            active += 1
            requests[endpoints]?.cancel = start(request) { result in
                Task { @MainActor in self.finish(endpoints, id: id, result: result) }
            }
            requests[endpoints]?.timeout = Task { [weak self, sleep] in
                do {
                    try await sleep(Self.timeout)
                    try Task.checkCancellation()
                    self?.finish(endpoints, id: id, result: .failure(URLError(.timedOut)), cancel: true)
                } catch { /* The request already ended. */ }
            }
        }
    }

    private func finish(_ endpoints: Endpoints, id: UUID, result: Result<RouteData, Error>, cancel: Bool = false) {
        removeCancelledWaiters()
        defer { startQueuedRequests() }
        guard let request = requests[endpoints], request.id == id else { return }
        removeRequest(at: endpoints, request: request, cancel: cancel)
        let route = result.flatMap { data in
            Result { try Self.walkingRoute(polyline: data.polyline, duration: data.duration, distance: data.distance) }
        }
        if case let .success(value) = route {
            let fetchedAt = now()
            routes = routes.filter { $0.value.expiresAt > fetchedAt }
            if routes.count >= Self.cacheCapacity,
               let oldest = routes.min(by: { $0.value.insertion < $1.value.insertion }) {
                routes[oldest.key] = nil
            }
            insertion += 1
            routes[endpoints] = (value, fetchedAt.addingTimeInterval(3_600), insertion)
        }
        for (_, waiter) in request.waiters.values { waiter.resume(with: route) }
    }

    private func removeRequest(at endpoints: Endpoints, request: Request, cancel: Bool) {
        requests[endpoints] = nil
        request.timeout?.cancel()
        if let stop = request.cancel {
            if cancel { stop() }
            active -= 1
        } else {
            queue.removeAll { $0 == endpoints }
        }
    }

    private static func mapItem(at coordinate: Coordinate) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.lat, longitude: coordinate.lon)
        return MKMapItem(location: location, address: nil)
    }

    private static func startWalkingRoute(_ request: MKDirections.Request, completion: @escaping Completion) -> () -> Void {
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let route = response?.routes.first {
                completion(.success((route.polyline, route.expectedTravelTime, route.distance)))
            } else {
                completion(.failure(error ?? MKError(.directionsNotFound)))
            }
        }
        return { directions.cancel() }
    }

    static func walkingRoute(polyline: MKPolyline, duration: TimeInterval, distance: CLLocationDistance) throws -> WalkingRoute {
        guard duration.isFinite, duration >= 0, distance.isFinite, distance >= 0, polyline.pointCount >= 2 else {
            throw MKError(.directionsNotFound)
        }
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: coordinates.count))
        guard coordinates.allSatisfy(CLLocationCoordinate2DIsValid) else { throw MKError(.directionsNotFound) }
        let geometry = GeoJSONLineString(type: "LineString", coordinates: coordinates.map { [$0.longitude, $0.latitude] })
        return WalkingRoute(geometry: geometry, duration: duration, distance: distance)
    }
}
