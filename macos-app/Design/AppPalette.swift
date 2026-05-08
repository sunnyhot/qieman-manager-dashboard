import AppKit
import SwiftUI

enum AppPalette {
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8

    static let brand = adaptive(light: rgb(0.10, 0.43, 0.39), dark: rgb(0.40, 0.82, 0.76))
    static let brandSoft = adaptive(light: rgb(0.84, 0.94, 0.91), dark: rgb(0.06, 0.20, 0.19))
    static let sand = adaptive(light: rgb(0.96, 0.94, 0.88), dark: rgb(0.13, 0.11, 0.08))
    static let paper = adaptive(light: rgb(0.99, 0.99, 0.96), dark: rgb(0.06, 0.07, 0.07))
    static let card = adaptive(light: rgb(0.97, 0.97, 0.93), dark: rgb(0.11, 0.12, 0.11))
    static let cardStrong = adaptive(light: rgb(1.00, 0.99, 0.96), dark: rgb(0.14, 0.15, 0.13))
    static let ink = adaptive(light: rgb(0.12, 0.16, 0.18), dark: rgb(0.90, 0.94, 0.92))
    static let muted = adaptive(light: rgb(0.38, 0.44, 0.44), dark: rgb(0.63, 0.69, 0.68))
    static let line = adaptive(light: rgb(0.82, 0.84, 0.78), dark: rgb(0.24, 0.29, 0.27))
    static let onBrand = adaptive(light: rgb(0.99, 1.00, 0.98), dark: rgb(0.03, 0.08, 0.07))

    static let positive = adaptive(light: rgb(0.18, 0.56, 0.32), dark: rgb(0.38, 0.82, 0.55))
    static let warning = adaptive(light: rgb(0.75, 0.45, 0.18), dark: rgb(0.96, 0.64, 0.33))
    static let danger = adaptive(light: rgb(0.73, 0.24, 0.22), dark: rgb(0.98, 0.42, 0.39))
    static let info = adaptive(light: rgb(0.18, 0.44, 0.68), dark: rgb(0.45, 0.68, 0.90))
    static let accentWarm = adaptive(light: rgb(0.66, 0.46, 0.20), dark: rgb(0.86, 0.62, 0.34))
    // Chinese market convention: gains are red, losses are green.
    static let marketGain = adaptive(light: rgb(0.73, 0.24, 0.22), dark: rgb(0.98, 0.42, 0.39))
    static let marketLoss = adaptive(light: rgb(0.18, 0.56, 0.32), dark: rgb(0.38, 0.82, 0.55))

    static func marketTint(for value: Double?) -> Color {
        guard let value else { return muted }
        if value > 0 { return marketGain }
        if value < 0 { return marketLoss }
        return muted
    }

    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                paper,
                sand.opacity(0.82),
                brandSoft.opacity(0.66),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                brandSoft.opacity(0.94),
                cardStrong.opacity(0.92),
                accentWarm.opacity(0.16),
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
