import SwiftUI

struct StopRowView: View {
    let stop: NearbyStop
    let line: LineInfo
    var color: Color = Color(.systemGray)

    var body: some View {
        HStack(spacing: 12) {
            TransportIconView(type: line.type, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))

                Text("\(line.name) \u{2192} \(line.direction)")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(.secondaryLabel))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview {
    List {
        ForEach(Array(PreviewData.stops.enumerated()), id: \.element.id) { index, stop in
            if let line = stop.lines.first {
                StopRowView(stop: stop, line: line, color: StopPalette.color(at: index))
            }
        }
    }
    .listStyle(.plain)
}
#endif
