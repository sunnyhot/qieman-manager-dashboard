import AppKit
import SwiftUI

enum AppPalette {
    static let cardRadius: CGFloat = 10
    static let panelRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8

    // MARK: - Brand & Surfaces

    /// Electric blue brand accent
    static let brand = adaptive(light: rgb(0.16, 0.40, 0.88), dark: rgb(0.31, 0.55, 1.00))
    static let brandSoft = adaptive(light: rgb(0.88, 0.93, 1.00), dark: rgb(0.10, 0.15, 0.28))
    /// Deep navy background
    static let surface = adaptive(light: rgb(0.94, 0.96, 0.99), dark: rgb(0.04, 0.05, 0.09))
    static let surfaceVariant = adaptive(light: rgb(0.87, 0.91, 0.96), dark: rgb(0.05, 0.07, 0.12))
    /// Card background — semi-transparent deep navy
    static let card = adaptive(light: rgb(1.00, 1.00, 1.00), dark: rgb(0.10, 0.12, 0.18))
    /// Card strong / elevated
    static let cardStrong = adaptive(light: rgb(0.95, 0.97, 1.00), dark: rgb(0.13, 0.15, 0.22))
    /// Card hover state
    static let cardHover = adaptive(light: rgb(0.90, 0.94, 0.99), dark: rgb(0.16, 0.18, 0.26))
    /// Primary text
    static let ink = adaptive(light: rgb(0.04, 0.06, 0.11), dark: rgb(0.92, 0.94, 0.98))
    /// Secondary / muted text
    static let muted = adaptive(light: rgb(0.28, 0.33, 0.43), dark: rgb(0.55, 0.58, 0.68))
    /// Border / line
    static let line = adaptive(light: rgb(0.70, 0.76, 0.86), dark: rgb(0.18, 0.20, 0.28))
    /// Text on brand-colored surfaces
    static let onBrand = adaptive(light: rgb(0.99, 0.99, 1.00), dark: rgb(0.99, 0.99, 1.00))

    // MARK: - Legacy Aliases (backward compat)

    static let sand = surfaceVariant
    static let paper = surface

    // MARK: - Semantic Colors

    static let positive = adaptive(light: rgb(0.02, 0.48, 0.28), dark: rgb(0.20, 0.78, 0.44))
    static let warning = adaptive(light: rgb(0.66, 0.40, 0.04), dark: rgb(0.96, 0.66, 0.24))
    static let danger = adaptive(light: rgb(0.70, 0.12, 0.12), dark: rgb(0.96, 0.36, 0.32))
    static let info = adaptive(light: rgb(0.10, 0.35, 0.70), dark: rgb(0.38, 0.62, 0.96))
    static let accentWarm = adaptive(light: rgb(0.62, 0.34, 0.08), dark: rgb(0.90, 0.62, 0.28))

    // MARK: - Chinese Market Convention (red=up, green=down)

    static let marketGain = adaptive(light: rgb(0.70, 0.12, 0.12), dark: rgb(0.96, 0.36, 0.32))
    static let marketLoss = adaptive(light: rgb(0.02, 0.48, 0.28), dark: rgb(0.20, 0.78, 0.44))

    static func marketTint(for value: Double?) -> Color {
        guard let value else { return muted }
        if value > 0 { return marketGain }
        if value < 0 { return marketLoss }
        return muted
    }

    // MARK: - Glass / Blur Helpers

    static var glassMaterial: Material { .ultraThinMaterial }

    static func glassBackground(radius: CGFloat = cardRadius) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(lineColor: Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    /// NSVisualEffectView.Material convenience aliases for consistent usage.
    enum Materials {
        /// Primary sidebar / panel background material.
        static let sidebar: NSVisualEffectView.Material = .sidebar
        /// Toolbar / header area material.
        static let toolbar: NSVisualEffectView.Material = .windowBackground
        /// Content area background material for subtle depth.
        static let content: NSVisualEffectView.Material = .underWindowBackground
        /// Elevated card / popover material.
        static let popover: NSVisualEffectView.Material = .hudWindow
    }

    // MARK: - Gradients

    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [
                surface,
                adaptive(light: rgb(0.90, 0.93, 0.98), dark: rgb(0.03, 0.05, 0.10)).opacity(0.92),
                brandSoft.opacity(0.62),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                brandSoft.opacity(0.96),
                cardStrong.opacity(0.94),
                brand.opacity(0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle glow gradient for card accent bars
    static func accentGlow(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Helpers

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

// MARK: - ShapeStyle helper for stroke with Color

extension ShapeStyle where Self == Color {
    static var lineColor: Color { AppPalette.line }
}

extension Shape {
    func stroke(lineColor: Color, lineWidth: CGFloat = 1) -> some View {
        self.stroke(lineColor, lineWidth: lineWidth)
    }
}
