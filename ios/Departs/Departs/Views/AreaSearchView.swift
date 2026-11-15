import SwiftUI
import MapKit

struct PlaceResult: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let coordinate: Coordinate
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
        guard query.count >= 2 else { loading = false; return }
        loading = true
        defer { if revision == requestID { loading = false } }
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            if let coordinate {
                request.region = MKCoordinateRegion(center: coordinate.clLocationCoordinate2D,
                                                    latitudinalMeters: 20_000, longitudinalMeters: 20_000)
            }
            let operation = MKLocalSearch(request: request)
            search = operation
            let response = try await operation.start()
            guard revision == requestID, !Task.isCancelled else { return }
            results = response.mapItems.enumerated().map { index, item in
                let coordinate = item.placemark.coordinate
                return PlaceResult(id: "\(requestID)-\(index)", name: item.name ?? "Selected place",
                                   subtitle: item.placemark.title ?? "",
                                   coordinate: .init(lat: coordinate.latitude, lon: coordinate.longitude))
            }
        } catch {
            guard revision == requestID, !Task.isCancelled else { return }
            self.error = "Couldn't search places. Check your connection and try again."
        }
    }
}

struct AreaSearchView: View {
    let near: Coordinate?
    let onSelect: (SearchArea) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var model = AreaSearchModel()
    @FocusState private var queryFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Stop, address, or place", text: $query)
                        .textInputAutocapitalization(.words).submitLabel(.search)
                        .focused($queryFocused)
                        .accessibilityIdentifier("area-query")
                } footer: {
                    Text("Choose where to look for departures. No location permission needed.")
                }
                if model.loading { ProgressView("Finding places…") }
                if let error = model.error { Text(error).foregroundStyle(.secondary) }
                ForEach(model.results) { place in
                    Button {
                        onSelect(.init(coordinate: place.coordinate, name: place.name, source: .chosen))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).foregroundStyle(.primary)
                            Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("area-result")
                }
                if query.count >= 2, !model.loading, model.error == nil, model.results.isEmpty {
                    Text("No places found. Try adding a city or street name.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choose an area").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) { await model.find(query, near: near) }
            .onAppear { queryFocused = true }
        }
    }
}
