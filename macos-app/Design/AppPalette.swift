import AppKit
import SwiftUI

enum AppPalette {
    // MARK: - Core
    static let brand = rgb(0.00, 0.90, 0.63)
    static let brandSoft = rgb(0.00, 0.90, 0.63, 0.12)
    static let onBrand = rgb(0.04, 0.10, 0.08)

    // MARK: - Surfaces
    static let canvas = rgb(0.04, 0.05, 0.10)
    static let paper = rgb(0.05, 0.07, 0.13)
    static let card = rgb(0.07, 0.10, 0.18)
    static let cardStrong = rgb(0.10, 0.13, 0.24)

    // MARK: - Text
    static let ink = rgb(0.89, 0.93, 0.95)
    static let muted = rgb(0.39, 0.45, 0.54)

    // MARK: - Borders
    static let line = rgb(0.12, 0.16, 0.24)
    static let lineBright = rgb(0.18, 0.23, 0.35)

    // MARK: - Semantic
    static let positive = rgb(0.00, 1.00, 0.53)
    static let negative = rgb(1.00, 0.23, 0.36)
    static let warning = rgb(1.00, 0.69, 0.13)
    static let info = rgb(0.22, 0.74, 0.97)
    static let accentWarm = rgb(1.00, 0.78, 0.26)
    static let danger = negative

    // MARK: - Gradients
    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                canvas,
                paper,
                rgb(0.00, 0.90, 0.63, 0.03),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                rgb(0.00, 0.90, 0.63, 0.08),
                rgb(0.00, 0.40, 0.80, 0.05),
                paper,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha))
    }
}
