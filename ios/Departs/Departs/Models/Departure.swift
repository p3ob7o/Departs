import Foundation

struct Departure: Codable, Identifiable {
    let id: UUID
    let time: String
    let realTime: Bool
    let delay: Double?
    let line: LineInfo?

    enum CodingKeys: String, CodingKey {
        case time, realTime, delay, line
    }

    init(time: String, realTime: Bool, delay: Double?, line: LineInfo? = nil) {
        self.id = UUID()
        self.time = time
        self.realTime = realTime
        self.delay = delay
        self.line = line
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.time = try container.decode(String.self, forKey: .time)
        self.realTime = try container.decode(Bool.self, forKey: .realTime)
        self.delay = try container.decodeIfPresent(Double.self, forKey: .delay)
        self.line = try container.decodeIfPresent(LineInfo.self, forKey: .line)
    }
}
