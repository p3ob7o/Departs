import Foundation

actor APIService {
    static let shared = APIService()

    private static let apiScheme = "https"
    private static let apiHost = "departs.vercel.app"
    private let decoder = JSONDecoder()
    private let session: URLSession
    private let baseURL: URL
    private var requests: [URL: Task<Data, Error>] = [:]

    init(session: URLSession = .shared, baseURL: URL? = nil) {
        self.session = session
        #if DEBUG
        let developmentURL = ProcessInfo.processInfo.environment["DEPARTS_API_BASE_URL"].flatMap(URL.init(string:))
        self.baseURL = baseURL ?? developmentURL ?? URL(string: "https://departs.vercel.app")!
        #else
        self.baseURL = baseURL ?? URL(string: "https://departs.vercel.app")!
        #endif
    }

    private func data(at productionURL: URL, refresh: Bool = false) async throws -> Data {
        guard var components = URLComponents(url: productionURL, resolvingAgainstBaseURL: false),
              let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        guard let url = components.url else { throw APIError.invalidURL }
        if let task = requests[url] { return try await task.value }
        let session = session
        let task = Task<Data, Error> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            if refresh { request.cachePolicy = .reloadIgnoringLocalCacheData }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw APIError.requestFailed
            }
            return data
        }
        requests[url] = task
        defer { requests[url] = nil }
        return try await task.value
    }

    func fetchNearbyStops(lat: Double, lon: Double) async throws -> [NearbyStop] {
        let url = try Self.nearbyStopsURL(lat: lat, lon: lon)
        let data = try await data(at: url)
        return try decoder.decode([NearbyStop].self, from: data).filter { $0.location.isValid }
    }

    func fetchDepartures(stopId: String, line: LineInfo) async throws -> [Departure] {
        let url = try Self.departuresURL(stopId: stopId, line: line)
        let data = try await data(at: url, refresh: true)
        return try decoder.decode([Departure].self, from: data)
    }

    func fetchDepartureBoards(stopIDs: [String]) async throws -> BatchDepartures {
        let bytes = try await data(at: Self.batchDeparturesURL(stopIDs: stopIDs), refresh: true)
        let response = try decoder.decode(BatchDepartures.self, from: bytes)
        guard TimeFormatter.parseISO(response.fetchedAt) != nil else { throw APIError.requestFailed }
        return response
    }

    func fetchDirections(from: Coordinate, to: Coordinate) async throws -> WalkingRoute {
        let url = try Self.directionsURL(from: from, to: to)
        let data = try await data(at: url)
        let route = try decoder.decode(WalkingRoute.self, from: data)
        guard route.duration.isFinite, route.duration >= 0, route.distance.isFinite, route.distance >= 0,
              route.geometry.type == "LineString", route.geometry.coordinates.count >= 2,
              route.geometry.clCoordinates.count == route.geometry.coordinates.count else { throw APIError.requestFailed }
        return route
    }

    static func nearbyStopsURL(lat: Double, lon: Double) throws -> URL {
        try makeURL(
            path: "/api/stops/nearby",
            queryItems: [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lon", value: String(lon)),
                URLQueryItem(name: "radius", value: String(TransitStore.radius)),
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

    static func batchDeparturesURL(stopIDs: [String]) throws -> URL {
        guard !stopIDs.isEmpty, stopIDs.count <= 50 else { throw APIError.invalidStopId }
        return try makeURL(path: "/api/departures", queryItems: [
            URLQueryItem(name: "stopIds", value: stopIDs.joined(separator: ","))
        ])
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
        // URLComponents leaves "+" as is, and servers read a raw "+" in a query as a space.
        // Separators are "&" and "=", so every "+" left here belongs to a name or value.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

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
        case .requestFailed: String(localized: "Couldn't connect. Please try again.")
        case .invalidStopId: String(localized: "This stop couldn't be found. Choose another stop.")
        case .invalidURL: String(localized: "Couldn't load this request. Please try again.")
        }
    }
}

struct BatchDepartures: Codable {
    struct Group: Codable {
        let line: LineInfo
        let departures: [Departure]
    }
    struct Board: Codable {
        let stopId: String
        let groups: [Group]
    }
    let fetchedAt: String
    let boards: [Board]
    let missing: [String]
}
