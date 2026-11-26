import MapKit

@MainActor
final class WalkingRouteService {
    static let shared = WalkingRouteService()

    private struct Endpoints: Hashable {
        let origin: Coordinate
        let destination: Coordinate
    }

    typealias RouteData = (polyline: MKPolyline, duration: TimeInterval, distance: CLLocationDistance)
    typealias Calculate = (MKDirections.Request) async throws -> RouteData

    private let calculate: Calculate
    private let now: () -> Date
    private var routes: [Endpoints: (route: WalkingRoute, expiresAt: Date)] = [:]

    init(now: @escaping () -> Date = { .now }, calculate: Calculate? = nil) {
        self.now = now
        self.calculate = calculate ?? Self.calculateWalkingRoute
    }

    func route(from origin: Coordinate, to destination: Coordinate) async throws -> WalkingRoute {
        try Task.checkCancellation()
        let endpoints = Endpoints(origin: origin, destination: destination)
        if let entry = routes[endpoints], entry.expiresAt > now() { return entry.route }

        let request = MKDirections.Request()
        request.source = Self.mapItem(at: origin)
        request.destination = Self.mapItem(at: destination)
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        let (polyline, duration, distance) = try await calculate(request)
        try Task.checkCancellation()
        let route = try Self.walkingRoute(polyline: polyline, duration: duration, distance: distance)
        let fetchedAt = now()
        routes = routes.filter { $0.value.expiresAt > fetchedAt }
        routes[endpoints] = (route, fetchedAt.addingTimeInterval(3_600))
        return route
    }

    private static func mapItem(at coordinate: Coordinate) -> MKMapItem {
        let location = CLLocation(latitude: coordinate.lat, longitude: coordinate.lon)
        return MKMapItem(location: location, address: nil)
    }

    private static func calculateWalkingRoute(_ request: MKDirections.Request) async throws -> RouteData {
        let directions = MKDirections(request: request)
        let response = try await withTaskCancellationHandler {
            try await directions.calculate()
        } onCancel: {
            Task { @MainActor in directions.cancel() }
        }
        guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
        return (route.polyline, route.expectedTravelTime, route.distance)
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
