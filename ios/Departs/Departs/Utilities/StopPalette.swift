import SwiftUI

enum StopPalette {
    // White glyphs meet 4.5:1 on every fill.
    static let colors: [Color] = ["3A6C9E", "A8553F", "3B7A47", "6B52A6", "276F65", "99425F", "756033", "4C6094", "806223", "346C50"].map { Color(hex: $0) }

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}
