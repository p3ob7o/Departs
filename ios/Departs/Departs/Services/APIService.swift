import Foundation

actor APIService {
    static let shared = APIService()

    private static let apiScheme = "https"
    private static let apiHost = "departs.vercel.app"
    private let decoder = JSONDecoder()

    func fetchNearbyStops(lat: Double, lon: Double) async throws -> [NearbyStop] {
        let url = try Self.nearbyStopsURL(lat: lat, lon: lon)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try decoder.decode([NearbyStop].self, from: data)
    }

    func fetchDepartures(stopId: String, line: LineInfo) async throws -> [Departure] {
        let url = try Self.departuresURL(stopId: stopId, line: line)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try decoder.decode([Departure].self, from: data)
    }

    func fetchDirections(from: Coordinate, to: Coordinate) async throws -> WalkingRoute {
        let url = try Self.directionsURL(from: from, to: to)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try decoder.decode(WalkingRoute.self, from: data)
    }

    static func nearbyStopsURL(lat: Double, lon: Double) throws -> URL {
        try makeURL(
            path: "/api/stops/nearby",
            queryItems: [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lon", value: String(lon)),
            ]
        )
    }

    static func departuresURL(stopId: String, line: LineInfo? = nil) throws -> URL {
        var queryItems = [URLQueryItem(name: "stopId", value: stopId)]
        if let line {
            queryItems.append(URLQueryItem(name: "lineName", value: line.name))
            queryItems.append(URLQueryItem(name: "direction", value: line.direction))
        }

        return try makeURL(
            path: "/api/departures",
            queryItems: queryItems
        )
    }

    static func directionsURL(from: Coordinate, to: Coordinate) throws -> URL {
        try makeURL(
            path: "/api/directions",
            queryItems: [
                URLQueryItem(name: "from", value: "\(from.lat),\(from.lon)"),
                URLQueryItem(name: "to", value: "\(to.lat),\(to.lon)"),
            ]
        )
    }

    private static func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = apiScheme
        components.host = apiHost
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }
}

enum APIError: LocalizedError {
    case requestFailed
    case invalidStopId
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .requestFailed: "Failed to connect to the server."
        case .invalidStopId: "Invalid stop identifier."
        case .invalidURL: "Invalid API request URL."
        }
    }
}
