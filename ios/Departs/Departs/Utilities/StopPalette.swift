import SwiftUI

enum StopPalette {
    /// Secondary information still needs readable contrast on list backgrounds.
    static let secondaryText = Color(uiColor: UIColor { traits in
        UIColor(Color(hex: traits.userInterfaceStyle == .dark ? "AEAEB2" : "636366"))
    })
    // White glyphs meet 4.5:1 on every fill.
    static let colors: [Color] = ["3A6C9E", "A8553F", "3B7A47", "6B52A6", "276F65", "99425F", "756033", "4C6094", "806223", "346C50"].map { Color(hex: $0) }

    static func modeColor(_ type: TransportType) -> Color {
        Color(uiColor: UIColor { traits in
            let hex: String
            switch type {
            case .tram: hex = "3A6C9E"
            case .bus: hex = "A8553F"
            case .rail: hex = "3B7A47"
            case .subway: hex = traits.userInterfaceStyle == .dark ? "8065B8" : "6B52A6"
            }
            return UIColor(Color(hex: hex))
        })
    }

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}
