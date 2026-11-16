import Foundation

/// A small derived fixture of the 16 November Vienna sample. Coordinates and
/// service identities are retained; times are relative, and raw responses are
/// not stored. Compiled only into the unit and UI test targets.
enum TransitSample {
    struct Service {
        let name: String
        let direction: String
        let mode: String
        var minutes: [Double] = [3, 9, 14, 20]
        var line: [String: Any] { ["name": name, "direction": "Wien \(direction)", "type": mode] }
    }
    static let platforms: [(String, String, Double, Double)] = [
        ("312", "Siebensterngasse", 48.201506, 16.349114),
        ("313", "Siebensterngasse", 48.201434, 16.348997),
        ("311", "Siebensterngasse", 48.201734, 16.348566),
        ("310", "Siebensterngasse", 48.202219, 16.349410),
        ("741", "Kirchengasse", 48.202207, 16.351458),
        ("739", "Kirchengasse", 48.202219, 16.352096),
        ("5045", "Burggasse/Neubaugasse", 48.203895, 16.349006),
        ("4130", "Burggasse/Neubaugasse", 48.203907, 16.348898),
        ("1506", "Westbahnstraße/Zieglergasse", 48.201871, 16.345359),
        ("5044", "Neubaugasse", 48.198560, 16.350012),
        ("3231", "Neubaugasse", 48.198512, 16.349886),
        ("3233", "Neubaugasse", 48.199243, 16.352473),
        ("4129", "Burggasse/Neubaugasse", 48.204236, 16.348413),
        ("5092", "Burggasse/Neubaugasse", 48.204458, 16.348889),
        ("1507", "Westbahnstraße/Zieglergasse", 48.201788, 16.344649),
        ("953", "Stiftgasse", 48.202320, 16.354198),
        ("3232", "Neubaugasse", 48.198081, 16.350874)
    ]
    static let services: [String: [Service]] = [
        "312": [.init(name: "13A", direction: "Skodagasse", mode: "bus", minutes: [2, 6, 10, 14]),
                .init(name: "N71", direction: "Kaiserebersdorf, Zinnergasse", mode: "bus", minutes: [166, 186])],
        "313": [.init(name: "13A", direction: "Hauptbahnhof", mode: "bus")],
        "311": [.init(name: "49", direction: "Parlament/Volkstheater", mode: "tram", minutes: [5, 15, 25, 35])],
        "310": [.init(name: "49", direction: "Hütteldorf, Bujattigasse", mode: "tram", minutes: [0.8, 10, 20, 30])],
        "741": [.init(name: "49", direction: "Parlament/Volkstheater", mode: "tram")],
        "739": [.init(name: "49", direction: "Hütteldorf, Bujattigasse", mode: "tram")],
        "5045": [.init(name: "13A", direction: "Skodagasse", mode: "bus")],
        "4130": [.init(name: "13A", direction: "Hauptbahnhof", mode: "bus")],
        "1506": [.init(name: "49", direction: "Hütteldorf, Bujattigasse", mode: "tram")],
        "5044": [.init(name: "13A", direction: "Skodagasse", mode: "bus")],
        "3231": [.init(name: "13A", direction: "Hauptbahnhof", mode: "bus")],
        "3233": [.init(name: "U3", direction: "Simmering", mode: "subway", minutes: [14, 18, 22, 26]),
                 .init(name: "U3", direction: "Ottakring", mode: "subway", minutes: [14, 18, 22, 26])],
        "4129": [.init(name: "48A", direction: "Parlament/Volkstheater", mode: "bus")],
        // Deliberately within the hour to test the third-destination rule.
        "5092": [.init(name: "13A", direction: "Volkstheater", mode: "bus")],
        "1507": [.init(name: "49", direction: "Parlament/Volkstheater", mode: "tram")],
        "953": [.init(name: "49", direction: "Parlament/Volkstheater", mode: "tram")],
        "3232": [.init(name: "14A", direction: "Reumannplatz", mode: "bus")]
    ]
    static var stops: [[String: Any]] {
        platforms.map { id, name, lat, lon in
            ["id": "77704_\(id)", "name": name, "type": services[id]!.first!.mode,
             "location": ["lat": lat, "lon": lon],
             // This platform returns a service absent from its metadata.
             "lines": id == "4130" ? [] : services[id]!.map(\.line)]
        }
    }
    static func departures(_ service: Service, at date: Date, count: Int = 2) -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Vienna")
        return service.minutes.prefix(count).enumerated().map { index, minutes in
            ["time": formatter.string(from: date.addingTimeInterval(minutes * 60)),
             "realTime": index == 0, "delay": index == 0 ? 65 : 0, "line": service.line]
        }
    }
    static func batch(at date: Date, missing: Set<String> = [], empty: Bool = false, changed: Bool = false) -> [String: Any] {
        let boards: [[String: Any]] = platforms.compactMap { id, _, _, _ in
            guard !missing.contains("77704_\(id)") else { return nil }
            var values = services[id]!
            if changed && id == "312" { values = [.init(name: "99A", direction: "New destination", mode: "bus")] }
            let groups: [[String: Any]] = empty ? [] : values.map { ["line": $0.line, "departures": departures($0, at: date)] }
            return ["stopId": "77704_\(id)", "groups": groups]
        }
        return ["fetchedAt": date.ISO8601Format(), "boards": boards, "missing": Array(missing).sorted()]
    }
}
