import Foundation

struct Departure: Codable, Identifiable {
    let time: String
    let realTime: Bool
    let delay: Double?

    var id: String { time }
}
