import SwiftUI

enum AppPalette {
    static let brand = Color(red: 0.15, green: 0.40, blue: 0.39)
    static let brandSoft = Color(red: 0.84, green: 0.92, blue: 0.89)
    static let sand = Color(red: 0.95, green: 0.92, blue: 0.86)
    static let paper = Color(red: 0.99, green: 0.98, blue: 0.95)
    static let card = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let cardStrong = Color(red: 0.985, green: 0.975, blue: 0.95)
    static let ink = Color(red: 0.16, green: 0.20, blue: 0.24)
    static let muted = Color(red: 0.42, green: 0.47, blue: 0.48)
    static let line = Color(red: 0.83, green: 0.81, blue: 0.76)

    static let positive = Color(red: 0.23, green: 0.56, blue: 0.34)
    static let warning = Color(red: 0.76, green: 0.46, blue: 0.25)
    static let danger = Color(red: 0.72, green: 0.28, blue: 0.25)
    static let info = Color(red: 0.24, green: 0.47, blue: 0.62)
    static let accentWarm = Color(red: 0.67, green: 0.49, blue: 0.26)

    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.93, blue: 0.88),
                Color(red: 0.98, green: 0.97, blue: 0.94),
                Color(red: 0.94, green: 0.95, blue: 0.93),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                brand.opacity(0.18),
                accentWarm.opacity(0.12),
                Color.white.opacity(0.6),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
