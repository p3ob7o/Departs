import SwiftUI

struct NearbyStopsView: View {
    let userCoordinate: Coordinate
    let stops: [NearbyStop]
    let stopColors: [String: Color]
    let onSelectStop: (NearbyStop) -> Void
    var onRefresh: (() async -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // App title
            Text("Departs")
                .font(.system(size: 22, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // Square map
            StopsMapView(
                userCoordinate: userCoordinate.clLocationCoordinate2D,
                stops: stops,
                stopColors: stopColors
            )
            .aspectRatio(1, contentMode: .fit)

            // Stop list
            if stops.isEmpty {
                VStack(spacing: 8) {
                    Text("No public transit stops nearby")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(.label))

                    Text("We couldn't find any stops nearby. Try moving to a different area.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stops) { stop in
                            Button {
                                onSelectStop(stop)
                            } label: {
                                StopRowView(
                                    stop: stop,
                                    color: stopColors[stop.id] ?? Color(.systemGray)
                                )
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .refreshable {
                    await onRefresh?()
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NearbyStopsView(
        userCoordinate: PreviewData.userCoordinate,
        stops: PreviewData.stops,
        stopColors: Dictionary(uniqueKeysWithValues: PreviewData.stops.enumerated().map {
            ($0.element.id, StopPalette.color(at: $0.offset))
        }),
        onSelectStop: { _ in }
    )
}
#endif
