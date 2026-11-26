import Foundation

actor APIService {
    static let shared = APIService()

    private static let apiScheme = "https"
    private static let apiHost = "api.departs.now"
    private static let productionBaseURL = URL(string: "\(apiScheme)://\(apiHost)")!
    private static let requestLimit = 4
    private let decoder = JSONDecoder()
    private let session: URLSession
    private let baseURL: URL
    private let cache: URLCache?
    private let now: @Sendable () -> Date
    private let waitForRetry: @Sendable (TimeInterval) async throws -> Void
    private var requests: [URL: Task<(Data, HTTPURLResponse), Error>] = [:]
    private var activeRequests = 0
    private var waitingRequests: [CheckedContinuation<Void, Never>] = []

    init(session: URLSession = .shared, baseURL: URL? = nil,
         now: @escaping @Sendable () -> Date = { .now },
         waitForRetry: @escaping @Sendable (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds($0))
         }) {
        self.session = session
        self.cache = session.configuration.urlCache
        self.now = now
        self.waitForRetry = waitForRetry
        #if DEBUG
        let developmentURL = ProcessInfo.processInfo.environment["DEPARTS_API_BASE_URL"].flatMap(URL.init(string:))
        self.baseURL = baseURL ?? developmentURL ?? Self.productionBaseURL
        #else
        self.baseURL = baseURL ?? Self.productionBaseURL
        #endif
    }

    private func request(at productionURL: URL) throws -> URLRequest {
        guard var components = URLComponents(url: productionURL, resolvingAgainstBaseURL: false),
              let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        guard let url = components.url else { throw APIError.invalidURL }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
    }

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw APIError.invalidURL }
        if let task = requests[url] { return try await task.value }
        let task = Task {
            var (bytes, response) = try await send(request)
            if response.statusCode == 429 {
                try await waitForRetry(Self.retryDelay(response.value(forHTTPHeaderField: "Retry-After"), now: now()))
                (bytes, response) = try await send(request)
            }
            // Treat a hosted 500 exactly like the original 502. Error bodies,
            // including HTML from the rate limiter, never reach the JSON decoder.
            guard response.statusCode == 200 else { throw APIError.requestFailed }
            return (bytes, response)
        }
        requests[url] = task
        defer { requests[url] = nil }
        return try await task.value
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if activeRequests == Self.requestLimit {
            await withCheckedContinuation { waitingRequests.append($0) }
        } else {
            activeRequests += 1
        }
        defer {
            if waitingRequests.isEmpty { activeRequests -= 1 }
            else { waitingRequests.removeFirst().resume() }
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.requestFailed }
        return (data, http)
    }

    private static func retryDelay(_ header: String?, now: Date) -> TimeInterval {
        guard let value = header?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return 2 }
        if value.utf8.allSatisfy({ (48...57).contains($0) }), let seconds = Double(value) {
            return min(seconds, 5)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return min(5, max(0, date.timeIntervalSince(now)))
            }
        }
        return 2
    }

    private func cachedValue<Value>(at url: URL, lifetime: TimeInterval,
                                    decode: (Data) throws -> Value) async throws -> Value {
        let request = try request(at: url)
        let expirationKey = "DepartsExpiration"
        if let entry = cache?.cachedResponse(for: request),
           let expiration = entry.userInfo?[expirationKey] as? Date, expiration > now(),
           let value = try? decode(entry.data) {
            return value
        }
        let (data, response) = try await load(request)
        let value = try decode(data)
        // Keep validated stops on the device even when the hosting layer disables HTTP caching.
        cache?.storeCachedResponse(CachedURLResponse(
            response: response, data: data, userInfo: [expirationKey: now().addingTimeInterval(lifetime)],
            storagePolicy: .allowed
        ), for: request)
        return value
    }

    func fetchNearbyStops(lat: Double, lon: Double) async throws -> [NearbyStop] {
        let url = try Self.nearbyStopsURL(lat: lat, lon: lon)
        return try await cachedValue(at: url, lifetime: 86_400) { data in
            try decoder.decode([NearbyStop].self, from: data).filter { $0.location.isValid }
        }
    }

    func fetchDepartures(stopId: String, line: LineInfo) async throws -> [Departure] {
        let url = try Self.departuresURL(stopId: stopId, line: line)
        let (data, _) = try await load(request(at: url))
        return try decoder.decode([Departure].self, from: data)
    }

    func fetchDepartureBoards(stopIDs: [String]) async throws -> BatchDepartures {
        let (bytes, _) = try await load(request(at: Self.batchDeparturesURL(stopIDs: stopIDs)))
        let response = try decoder.decode(BatchDepartures.self, from: bytes)
        guard TimeFormatter.parseISO(response.fetchedAt) != nil else { throw APIError.requestFailed }
        return response
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
