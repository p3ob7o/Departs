import SwiftUI

struct StopRowView: View {
    let stop: NearbyStop
    var color: Color = Color(.systemGray)

    var body: some View {
        HStack(spacing: 12) {
            TransportIconView(type: stop.type, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.type.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))

                if let firstLine = stop.lines.first {
                    Text("\(firstLine.name) to \(firstLine.direction)")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        ForEach(Array(PreviewData.stops.enumerated()), id: \.element.id) { index, stop in
            StopRowView(stop: stop, color: StopPalette.color(at: index))
        }
    }
    .listStyle(.plain)
}
