import Foundation

actor APIService {
    static let shared = APIService()

    private let baseURL = "https://departs.vercel.app"
    private let decoder = JSONDecoder()

    func fetchNearbyStops(lat: Double, lon: Double) async throws -> [NearbyStop] {
        let url = URL(string: "\(baseURL)/api/stops/nearby?lat=\(lat)&lon=\(lon)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try decoder.decode([NearbyStop].self, from: data)
    }

    func fetchDepartures(stopId: String) async throws -> [Departure] {
        guard let encoded = stopId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidStopId
        }
        let url = URL(string: "\(baseURL)/api/departures?stopId=\(encoded)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try decoder.decode([Departure].self, from: data)
    }

    func fetchDirections(from: Coordinate, to: Coordinate) async throws -> WalkingRoute {
        let url = URL(string: "\(baseURL)/api/directions?from=\(from.lat),\(from.lon)&to=\(to.lat),\(to.lon)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try decoder.decode(WalkingRoute.self, from: data)
    }
}

enum APIError: LocalizedError {
    case requestFailed
    case invalidStopId

    var errorDescription: String? {
        switch self {
        case .requestFailed: "Failed to connect to the server."
        case .invalidStopId: "Invalid stop identifier."
        }
    }
}
