import SwiftUI

struct DepartureDetailView: View {
    let stop: NearbyStop
    let stopColor: Color
    let userCoordinate: Coordinate

    @State private var viewModel = DepartureDetailViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Route map (5:4 aspect ratio)
            RouteMapView(
                userCoordinate: userCoordinate.clLocationCoordinate2D,
                stop: stop,
                stopColor: stopColor,
                walkingRoute: viewModel.walkingRoute
            )
            .aspectRatio(5.0 / 4.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .horizontal)

            // Content card
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Heading
                    Text("Departures")
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
                        Text("\(max(1, route.walkingMinutes)) min walk")
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
            .background(Color(.systemBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 3, y: -1)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Departs")
        .navigationBarTitleDisplayMode(.inline)
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
    NavigationStack {
        DepartureDetailView(
            stop: PreviewData.stops[0],
            stopColor: StopPalette.colors[0],
            userCoordinate: PreviewData.userCoordinate
        )
    }
}
#endif
