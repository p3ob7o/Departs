import SwiftUI

struct ContentView: View {
    @State private var locationService = LocationService()
    @State private var stopsViewModel = NearbyStopsViewModel()
    @State private var selectedStop: NearbyStop?

    var body: some View {
        Group {
            switch locationService.state {
            case .idle, .requesting:
                LoadingView()

            case .denied:
                ErrorView(type: .permission) {
                    locationService.requestLocation()
                }

            case .failed:
                ErrorView(type: .network) {
                    locationService.requestLocation()
                }

            case .located(let coordinate):
                if stopsViewModel.isLoading {
                    LoadingView()
                } else if stopsViewModel.error != nil {
                    ErrorView(type: .network) {
                        Task {
                            await stopsViewModel.loadStops(near: coordinate)
                        }
                    }
                } else if let stop = selectedStop {
                    DepartureDetailView(
                        stop: stop,
                        stopColor: stopsViewModel.stopColors[stop.id] ?? Color(.systemGray),
                        userCoordinate: coordinate,
                        onBack: { selectedStop = nil }
                    )
                    .transition(.move(edge: .trailing))
                } else {
                    NearbyStopsView(
                        userCoordinate: coordinate,
                        stops: stopsViewModel.stops,
                        stopColors: stopsViewModel.stopColors,
                        onSelectStop: { stop in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedStop = stop
                            }
                        },
                        onRefresh: {
                            locationService.requestLocation()
                            // Wait for updated location
                            for _ in 0..<100 {
                                try? await Task.sleep(for: .milliseconds(100))
                                if case .located = locationService.state { break }
                            }
                            if case .located(let coord) = locationService.state {
                                await stopsViewModel.loadStops(near: coord)
                            }
                        }
                    )
                    .transition(.move(edge: .leading))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedStop?.id)
        .onAppear {
            locationService.requestLocation()
        }
        .onChange(of: locationService.state) { _, newState in
            if case .located(let coordinate) = newState {
                Task {
                    await stopsViewModel.loadStops(near: coordinate)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
