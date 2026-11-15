import SwiftUI

struct TransportIconView: View {
    let type: TransportType
    var color: Color = Color(.systemGray)

    @ScaledMetric(relativeTo: .body) private var diameter = 40.0

    var body: some View {
        Text(type.label)
            .font(.body.bold())
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(color)
            .clipShape(Circle())
    }
}

#Preview {
    HStack(spacing: 12) {
        TransportIconView(type: .subway, color: StopPalette.colors[0])
        TransportIconView(type: .tram, color: StopPalette.colors[1])
        TransportIconView(type: .bus, color: StopPalette.colors[2])
        TransportIconView(type: .rail, color: StopPalette.colors[3])
    }
    .padding()
}
