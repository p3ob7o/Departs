import Foundation
import AppIntents

@MainActor
@Observable
final class RouteNavigation {
    static let shared = RouteNavigation()
    var pinnedRouteID: String?

    static func pinID(from url: URL) -> String? {
        guard url.scheme == "departs", url.host == "pin",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
              !id.isEmpty, id.utf8.count <= 4096 else { return nil }
        return id
    }
}

struct PinnedRouteEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pinned route")
    static var defaultQuery = PinnedRouteQuery()
    let id: String
    let title: String
    let stopName: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)", subtitle: "\(stopName)") }

    init(_ selection: StopLineSelection) {
        id = selection.id
        title = "\(selection.line.shortName) → \(selection.line.displayDirection)"
        stopName = selection.stop.name
    }
}

struct PinnedRouteQuery: EntityQuery {
    #if DEBUG
    private let defaultsSuiteName: String?

    init() { defaultsSuiteName = nil }
    init(defaultsSuiteName: String) { self.defaultsSuiteName = defaultsSuiteName }
    #endif

    func entities(for identifiers: [String]) async throws -> [PinnedRouteEntity] {
        loadPins().filter { identifiers.contains($0.id) }.map(PinnedRouteEntity.init)
    }

    func suggestedEntities() async throws -> [PinnedRouteEntity] {
        loadPins().map(PinnedRouteEntity.init)
    }

    private func loadPins() -> [StopLineSelection] {
        #if DEBUG
        if let defaultsSuiteName, let defaults = UserDefaults(suiteName: defaultsSuiteName) {
            return TransitPersistence(defaults: defaults).loadPins()
        }
        #endif
        return TransitPersistence().loadPins()
    }
}

struct OpenPinnedRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Open pinned route"
    static var description = IntentDescription("Open a saved stop and direction and refresh its departure times.")
    static var openAppWhenRun = true
    @Parameter(title: "Pinned route") var route: PinnedRouteEntity
    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$route)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        RouteNavigation.shared.pinnedRouteID = route.id
        return .result()
    }
}

struct DepartsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenPinnedRouteIntent(),
                    phrases: ["Open \(\.$route) in \(.applicationName)"],
                    shortTitle: "Open pinned route", systemImageName: "pin.fill")
    }
}
