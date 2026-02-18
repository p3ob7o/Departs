import SwiftUI

struct NearbyStopsView: View {
    let userCoordinate: Coordinate
    let stops: [NearbyStop]
    let stopColors: [String: Color]
    var isLoading: Bool = false
    let onSelectStop: (NearbyStop) -> Void
    var onRefresh: (() async -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Map (5:4 aspect ratio)
            StopsMapView(
                userCoordinate: userCoordinate.clLocationCoordinate2D,
                stops: stops,
                stopColors: stopColors
            )
            .aspectRatio(5.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .horizontal)

            // Content card
            Group {
                if isLoading && stops.isEmpty {
                    VStack(spacing: 0) {
                        sectionHeader

                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonRowView()
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                    .padding(.horizontal, 16)
                } else if stops.isEmpty {
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
                            sectionHeader

                            ForEach(stops) { stop in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onSelectStop(stop)
                                } label: {
                                    StopRowView(
                                        stop: stop,
                                        color: stopColors[stop.id] ?? Color(.systemGray)
                                    )
                                }
                                .buttonStyle(HighlightButtonStyle())

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
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 3, y: -1)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Departs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sectionHeader: some View {
        Text("NEARBY STOPS")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(.secondaryLabel))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

private struct SkeletonRowView: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray6))
                    .frame(width: 180, height: 12)
            }

            Spacer()
        }
        .padding(.vertical, 16)
    }
}

private struct HighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemGray5) : .clear)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        NearbyStopsView(
            userCoordinate: PreviewData.userCoordinate,
            stops: PreviewData.stops,
            stopColors: Dictionary(uniqueKeysWithValues: PreviewData.stops.enumerated().map {
                ($0.element.id, StopPalette.color(at: $0.offset))
            }),
            onSelectStop: { _ in }
        )
    }
}
#endif
