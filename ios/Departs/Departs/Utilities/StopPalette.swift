import SwiftUI

enum StopPalette {
    static let colors: [Color] = [
        Color(hex: "7BA3C9"), // powder blue
        Color(hex: "C9887B"), // terra cotta
        Color(hex: "82B882"), // soft green
        Color(hex: "9B82C9"), // soft purple
        Color(hex: "7BC9BD"), // teal
        Color(hex: "C97B95"), // soft rose
        Color(hex: "B8A87B"), // sand
        Color(hex: "7B95C9"), // periwinkle
        Color(hex: "C9B27B"), // gold
        Color(hex: "82C9A3"), // mint
    ]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}
