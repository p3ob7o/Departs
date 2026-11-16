import MapKit
import SwiftUI

struct PlaceResult: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let coordinate: Coordinate
    var transit = false
    var distance: Double? = nil
    var symbol = "mappin"
}

@MainActor
@Observable
final class AreaSearchModel {
    private(set) var results: [PlaceResult] = []
    private(set) var loading = false
    private(set) var error: String?
    @ObservationIgnored private var search: MKLocalSearch?
    @ObservationIgnored private var revision = UUID()

    func find(_ query: String, near coordinate: Coordinate?) async {
        search?.cancel()
        let requestID = UUID()
        revision = requestID
        results = []
        error = nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            loading = false
            return
        }
        loading = true
        defer { if revision == requestID { loading = false } }
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            #if DEBUG
                if ProcessInfo.processInfo.environment["DEPARTS_TEST_PLACE_SEARCH"] == "1",
                    let base = ProcessInfo.processInfo.environment["DEPARTS_API_BASE_URL"].flatMap(
                        URL.init(string:))
                {
                    let (data, _) = try await URLSession.shared.data(
                        from: base.appendingPathComponent("test/places"))
                    let areas = try JSONDecoder().decode([SearchArea].self, from: data)
                    guard revision == requestID, !Task.isCancelled else { return }
                    results = areas.filter { $0.coordinate.isValid }.enumerated().map { index, area in
                        PlaceResult(
                            id: "\(requestID)-\(index)", name: area.name, subtitle: "Vienna, Austria",
                            coordinate: area.coordinate, transit: true,
                            distance: coordinate?.distance(to: area.coordinate), symbol: "tram")
                    }
                    return
                }
            #endif
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            if let coordinate {
                request.region = MKCoordinateRegion(
                    center: coordinate.clLocationCoordinate2D,
                    latitudinalMeters: 20_000, longitudinalMeters: 20_000)
            }
            let operation = MKLocalSearch(request: request)
            search = operation
            let response = try await operation.start()
            guard revision == requestID, !Task.isCancelled else { return }
            let nearCoordinate = coordinate
            let places = response.mapItems.enumerated().map { index, item in
                let coordinate = item.placemark.coordinate
                return PlaceResult(
                    id: "\(requestID)-\(index)", name: item.name ?? String(localized: "Selected place"),
                    subtitle: item.placemark.title ?? "",
                    coordinate: .init(lat: coordinate.latitude, lon: coordinate.longitude),
                    transit: item.pointOfInterestCategory == .publicTransport,
                    distance: nearDistance(item.placemark.coordinate, from: nearCoordinate),
                    symbol: Self.symbol(for: item.pointOfInterestCategory))
            }
            results = Self.transitFirst(places)
        } catch {
            guard revision == requestID, !Task.isCancelled else { return }
            self.error = String(localized: "Couldn't search places. Check your connection and try again.")
        }
    }
    private func nearDistance(_ point: CLLocationCoordinate2D, from origin: Coordinate?) -> Double? {
        origin?.distance(to: .init(lat: point.latitude, lon: point.longitude))
    }

    static func transitFirst(_ places: [PlaceResult]) -> [PlaceResult] {
        places.filter(\.transit) + places.filter { !$0.transit }
    }

    private static func symbol(for category: MKPointOfInterestCategory?) -> String {
        switch category {
        case .publicTransport: "tram"
        case .cafe: "cup.and.saucer"
        case .restaurant: "fork.knife"
        case .hotel: "bed.double"
        case .park: "leaf"
        case .hospital: "cross.case"
        default: "mappin"
        }
    }
}

struct AreaSearchView: View {
    let near: Coordinate?
    var recentAreas: [SearchArea] = []
    var onLocate: () -> Void = {}
    let onSelect: (SearchArea) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var model = AreaSearchModel()
    @FocusState private var queryFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").accessibilityHidden(true)
                        TextField("", text: $query, axis: .vertical)
                            .frame(minHeight: 44)
                            .textInputAutocapitalization(.words).submitLabel(.search)
                            .focused($queryFocused)
                            .onSubmit { queryFocused = false }
                            .onChange(of: query) { _, value in
                                // A wrapping text field can insert a newline for
                                // Return. Search is still a single logical query.
                                if value.contains(where: \.isNewline) {
                                    query = value.split(whereSeparator: \.isNewline).joined(separator: " ")
                                    queryFocused = false
                                }
                            }
                            .accessibilityLabel("Stop, address, or place")
                            .accessibilityIdentifier("area-query")
                    }.frame(minHeight: 44)
                } header: {
                    Text("Stop, address, or place").textCase(nil)
                        .foregroundStyle(StopPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if query.isEmpty {
                    Section {
                        Button(action: onLocate) {
                            Label("Current location", systemImage: "location.fill").frame(minHeight: 44)
                        }
                    }
                    if !recentAreas.isEmpty {
                        Section {
                            ForEach(Array(recentAreas.enumerated()), id: \.offset) { _, area in
                                Button {
                                    onSelect(area)
                                } label: {
                                    Label(area.name, systemImage: "clock.arrow.circlepath").frame(minHeight: 44)
                                }.accessibilityIdentifier("recent-area")
                            }
                        } header: {
                            Text("Recent places").foregroundStyle(StopPalette.secondaryText).textCase(nil)
                        }
                    }
                }
                if model.loading { ProgressView("Finding places…") }
                if let error = model.error { Text(error).foregroundStyle(StopPalette.secondaryText) }
                ForEach(model.results) { place in
                    Button {
                        onSelect(.init(coordinate: place.coordinate, name: place.name, source: .chosen))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(place.name, systemImage: place.symbol).foregroundStyle(Color.primary)
                            if let distance = place.distance {
                                Text("\(TransitFormat.distance(distance)) away").font(.caption).foregroundStyle(StopPalette.secondaryText)
                            }
                            if !place.subtitle.isEmpty { Text(place.subtitle).font(.caption).foregroundStyle(StopPalette.secondaryText) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("area-result")
                }
                if query.count >= 2, !model.loading, model.error == nil, model.results.isEmpty {
                    Text("No places found. Try adding a city or street name.").foregroundStyle(StopPalette.secondaryText)
                }
            }
            .modifier(ReadableList())
            .navigationTitle("Choose an area").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("cancel-area-search")
                }
            }
            .task(id: query) { await model.find(query, near: near) }
        }
    }
}
