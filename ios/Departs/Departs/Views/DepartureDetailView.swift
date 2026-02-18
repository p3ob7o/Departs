import SwiftUI

struct DepartureDetailView: View {
    let stop: NearbyStop
    let stopColor: Color
    let userCoordinate: Coordinate
    let onBack: () -> Void

    @State private var viewModel = DepartureDetailViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button and app title
            ZStack {
                Text("Departs")
                    .font(.system(size: 22, weight: .bold))

                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 17))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)

            // Route map
            RouteMapView(
                userCoordinate: userCoordinate.clLocationCoordinate2D,
                stop: stop,
                stopColor: stopColor,
                walkingRoute: viewModel.walkingRoute
            )
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .horizontal)

            // Detail content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Heading
                    Text("Departures:")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(.label))

                    // Line info
                    if let firstLine = stop.lines.first {
                        Text("\(stop.type.displayName) \(firstLine.name) to \(firstLine.direction)")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.top, 8)
                    }

                    // Walking time
                    if let route = viewModel.walkingRoute {
                        Text("\(route.walkingMinutes) min walk")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(.secondaryLabel))
                            .padding(.top, 4)
                    }

                    // Departure rows
                    VStack(spacing: 0) {
                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text("Loading departures...")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(.secondaryLabel))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else if viewModel.error != nil {
                            Text("Couldn't load departure times.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else if viewModel.departures.isEmpty {
                            Text("No upcoming departures found.")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(viewModel.departures) { departure in
                                DepartureRowView(departure: departure)
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(16)
            }
        }
        .task {
            await viewModel.load(
                stopId: stop.id,
                from: userCoordinate,
                to: stop.location
            )
        }
    }
}

#if DEBUG
#Preview {
    DepartureDetailView(
        stop: PreviewData.stops[0],
        stopColor: StopPalette.colors[0],
        userCoordinate: PreviewData.userCoordinate,
        onBack: { }
    )
}
#endif
