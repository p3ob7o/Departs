import Foundation

struct TransitPersistence {
    let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) {
        #if DEBUG
        let testDefaults = ProcessInfo.processInfo.environment["DEPARTS_DEFAULTS_SUITE"].flatMap(UserDefaults.init(suiteName:))
        self.defaults = defaults ?? testDefaults ?? .standard
        #else
        self.defaults = defaults ?? .standard
        #endif
    }

    private static let pinsKey = "departs.pins.v1"
    private static let snapshotKey = "departs.nearby.v1"
    private static let boardsKey = "departs.boards.v1"

    func loadRecentAreas() -> [SearchArea] {
        let areas: [SearchArea] = read("departs.recentAreas.v1") ?? []
        return Array(areas.filter { $0.source == .chosen && $0.coordinate.isValid }.prefix(5))
    }
    func saveRecentAreas(_ areas: [SearchArea]) { write(Array(areas.prefix(5)), key: "departs.recentAreas.v1") }

    func loadPins() -> [StopLineSelection] { read(Self.pinsKey) ?? [] }
    func savePins(_ pins: [StopLineSelection]) { write(pins, key: Self.pinsKey) }
    func loadNearby() -> NearbySnapshot? { read(Self.snapshotKey) }
    func saveNearby(_ snapshot: NearbySnapshot) { write(snapshot, key: Self.snapshotKey) }
    func loadBoards() -> [String: DepartureBoard] { read(Self.boardsKey) ?? [:] }
    func loadHome() -> HomeSnapshot? { read("departs.home.v2") }
    func saveHome(_ snapshot: HomeSnapshot) { write(snapshot, key: "departs.home.v2") }

    func saveBoards(_ boards: [String: DepartureBoard]) {
        let recent = boards.sorted { $0.value.checkedAt > $1.value.checkedAt }.prefix(40)
        write(Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0.value) }), key: Self.boardsKey)
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
