import AppKit
import SwiftUI

enum AppPalette {
    static let brand = adaptive(light: rgb(0.15, 0.40, 0.39), dark: rgb(0.31, 0.67, 0.63))
    static let brandSoft = adaptive(light: rgb(0.84, 0.92, 0.89), dark: rgb(0.10, 0.22, 0.21))
    static let sand = adaptive(light: rgb(0.95, 0.92, 0.86), dark: rgb(0.18, 0.16, 0.13))
    static let paper = adaptive(light: rgb(0.99, 0.98, 0.95), dark: rgb(0.08, 0.09, 0.10))
    static let card = adaptive(light: rgb(0.97, 0.95, 0.91), dark: rgb(0.13, 0.13, 0.12))
    static let cardStrong = adaptive(light: rgb(0.985, 0.975, 0.95), dark: rgb(0.16, 0.16, 0.145))
    static let ink = adaptive(light: rgb(0.16, 0.20, 0.24), dark: rgb(0.90, 0.92, 0.91))
    static let muted = adaptive(light: rgb(0.42, 0.47, 0.48), dark: rgb(0.64, 0.68, 0.68))
    static let line = adaptive(light: rgb(0.83, 0.81, 0.76), dark: rgb(0.29, 0.30, 0.29))
    static let onBrand = adaptive(light: rgb(1.00, 1.00, 1.00), dark: rgb(0.04, 0.08, 0.08))

    static let positive = adaptive(light: rgb(0.23, 0.56, 0.34), dark: rgb(0.46, 0.78, 0.53))
    static let warning = adaptive(light: rgb(0.76, 0.46, 0.25), dark: rgb(0.96, 0.64, 0.35))
    static let danger = adaptive(light: rgb(0.72, 0.28, 0.25), dark: rgb(0.96, 0.44, 0.40))
    static let info = adaptive(light: rgb(0.24, 0.47, 0.62), dark: rgb(0.50, 0.72, 0.88))
    static let accentWarm = adaptive(light: rgb(0.67, 0.49, 0.26), dark: rgb(0.90, 0.70, 0.42))

    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                sand,
                paper,
                brandSoft.opacity(0.72),
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
                paper.opacity(0.62),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return dark
            default:
                return light
            }
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
