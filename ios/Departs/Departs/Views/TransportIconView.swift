import SwiftUI

struct TransportIconView: View {
    let type: TransportType
    var color: Color = Color(.systemGray)

    var body: some View {
        Text(type.label)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
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
