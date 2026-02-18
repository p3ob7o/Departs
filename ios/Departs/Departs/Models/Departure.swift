import Foundation

struct Departure: Codable, Identifiable {
    let id: UUID
    let time: String
    let realTime: Bool
    let delay: Double?

    enum CodingKeys: String, CodingKey {
        case time, realTime, delay
    }

    init(time: String, realTime: Bool, delay: Double?) {
        self.id = UUID()
        self.time = time
        self.realTime = realTime
        self.delay = delay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.time = try container.decode(String.self, forKey: .time)
        self.realTime = try container.decode(Bool.self, forKey: .realTime)
        self.delay = try container.decodeIfPresent(Double.self, forKey: .delay)
    }
}
