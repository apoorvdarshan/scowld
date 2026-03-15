import SwiftUI

// MARK: - Amica Theme Colors

extension ShapeStyle where Self == Color {
    /// Bright sky blue / cyan — visible against dark backgrounds
    static var amicaBlue: Color {
        Color(red: 0.4, green: 0.8, blue: 1.0)
    }
}

extension Color {
    /// Bright sky blue / cyan — visible against dark backgrounds
    static let amicaBlue = Color(red: 0.4, green: 0.8, blue: 1.0)
}
