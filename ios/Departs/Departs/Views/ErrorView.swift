import SwiftUI

struct ErrorView: View {
    enum ErrorType {
        case permission
        case network
        case empty

        var title: String {
            switch self {
            case .permission: "Location Permission Required"
            case .network: "Couldn't Load Stops"
            case .empty: "No Public Transit Stops Nearby"
            }
        }

        var description: String {
            switch self {
            case .permission:
                "Departs needs your location to find nearby transit stops. Please enable location access in Settings."
            case .network:
                "We couldn't connect to the transit data service. Check your connection and try again."
            case .empty:
                "We couldn't find any stops within 400m. Try moving to a different area."
            }
        }
    }

    let type: ErrorType
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Text(type.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(.label))

            Text(type.description)
                .font(.system(size: 15))
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)

            if type != .empty, let onRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("Permission") {
    ErrorView(type: .permission) { }
}

#Preview("Network") {
    ErrorView(type: .network) { }
}
