import SwiftUI

struct LoadingView: View {
    var message: String = "Finding nearby stops..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    LoadingView()
}
