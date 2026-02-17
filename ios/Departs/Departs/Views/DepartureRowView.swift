import SwiftUI

struct DepartureRowView: View {
    let departure: Departure

    var body: some View {
        HStack {
            Text(TimeFormatter.formatTime(departure.time))
                .font(.system(size: 17))
                .foregroundStyle(Color(.label))

            Spacer()

            if departure.realTime {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }

            if let delay = departure.delay {
                if delay > 0 {
                    Text("+\(Int(delay / 60)) min")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                } else {
                    Text("On time")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
            }

            Image(systemName: "clock")
                .font(.system(size: 16))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.leading, 4)
        }
        .frame(height: 52)
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(PreviewData.departures) { dep in
            DepartureRowView(departure: dep)
            Divider()
        }
    }
    .padding(.horizontal)
}
