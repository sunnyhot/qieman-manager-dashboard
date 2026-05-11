import AppKit
import Foundation
import SwiftUI

enum MenuBarTickerTextColorMode: String, Codable, CaseIterable, Identifiable {
    case system
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .custom: return "自定义"
        }
    }
}

enum MenuBarTickerDimensionMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "自动"
        case .manual: return "手动"
        }
    }
}

enum MenuBarTickerLayoutMode: String, Codable, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .horizontal: return "左右"
        case .vertical: return "上下"
        }
    }

    var icon: String {
        switch self {
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        }
    }
}

struct MenuBarTickerAppearance: Codable, Hashable {
    var textColorMode: MenuBarTickerTextColorMode
    var customTextColorHex: String
    var fontSize: Double
    var isBold: Bool
    var layoutMode: MenuBarTickerLayoutMode
    var spacingMode: MenuBarTickerDimensionMode
    var manualSpacing: Double
    var widthMode: MenuBarTickerDimensionMode
    var manualWidth: Double

    static let minFontSize: Double = 7
    static let maxFontSize: Double = 14
    static let minManualSpacing: Double = 0
    static let maxManualSpacing: Double = 28
    static let minManualWidth: Double = 72
    static let maxManualWidth: Double = 360

    static let `default` = MenuBarTickerAppearance(
        textColorMode: .system,
        customTextColorHex: "#1F292E",
        fontSize: 9,
        isBold: false,
        layoutMode: .horizontal,
        spacingMode: .automatic,
        manualSpacing: 10,
        widthMode: .automatic,
        manualWidth: 180
    )

    private enum AppearanceCodingKeys: String, CodingKey {
        case textColorMode, customTextColorHex, fontSize, isBold
        case layoutMode, spacingMode, manualSpacing, widthMode, manualWidth
    }

    init(
        textColorMode: MenuBarTickerTextColorMode = .system,
        customTextColorHex: String = "#1F292E",
        fontSize: Double = 9,
        isBold: Bool = false,
        layoutMode: MenuBarTickerLayoutMode = .horizontal,
        spacingMode: MenuBarTickerDimensionMode = .automatic,
        manualSpacing: Double = 10,
        widthMode: MenuBarTickerDimensionMode = .automatic,
        manualWidth: Double = 180
    ) {
        self.textColorMode = textColorMode
        self.customTextColorHex = customTextColorHex
        self.fontSize = fontSize
        self.isBold = isBold
        self.layoutMode = layoutMode
        self.spacingMode = spacingMode
        self.manualSpacing = manualSpacing
        self.widthMode = widthMode
        self.manualWidth = manualWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AppearanceCodingKeys.self)
        textColorMode = try c.decodeIfPresent(MenuBarTickerTextColorMode.self, forKey: .textColorMode) ?? .system
        customTextColorHex = try c.decodeIfPresent(String.self, forKey: .customTextColorHex) ?? "#1F292E"
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 9
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        layoutMode = try c.decodeIfPresent(MenuBarTickerLayoutMode.self, forKey: .layoutMode) ?? .horizontal
        spacingMode = try c.decodeIfPresent(MenuBarTickerDimensionMode.self, forKey: .spacingMode) ?? .automatic
        manualSpacing = try c.decodeIfPresent(Double.self, forKey: .manualSpacing) ?? 10
        widthMode = try c.decodeIfPresent(MenuBarTickerDimensionMode.self, forKey: .widthMode) ?? .automatic
        manualWidth = try c.decodeIfPresent(Double.self, forKey: .manualWidth) ?? 180
    }

    func normalized() -> MenuBarTickerAppearance {
        var copy = self
        copy.fontSize = min(max(copy.fontSize, Self.minFontSize), Self.maxFontSize)
        copy.manualSpacing = min(max(copy.manualSpacing, Self.minManualSpacing), Self.maxManualSpacing)
        copy.manualWidth = min(max(copy.manualWidth, Self.minManualWidth), Self.maxManualWidth)
        if MenuBarTickerAppearance.nsColor(hex: copy.customTextColorHex) == nil {
            copy.customTextColorHex = Self.default.customTextColorHex
        }
        return copy
    }

    var fontWeight: NSFont.Weight {
        isBold ? .bold : .medium
    }

    var swiftUIColor: Color {
        switch textColorMode {
        case .system:
            return AppPalette.ink
        case .custom:
            return Color(nsColor: MenuBarTickerAppearance.nsColor(hex: customTextColorHex) ?? .labelColor)
        }
    }

    var nsColor: NSColor? {
        switch textColorMode {
        case .system:
            return nil
        case .custom:
            return MenuBarTickerAppearance.nsColor(hex: customTextColorHex) ?? .labelColor
        }
    }

    static func normalizedHex(from color: NSColor) -> String {
        let converted = color.usingColorSpace(.sRGB) ?? color
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func nsColor(hex: String) -> NSColor? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard raw.count == 6, let value = Int(raw, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

struct MenuBarTickerSettings: Codable, Hashable {
    var isEnabled: Bool
    var maxVisibleItems: Int
    var selections: [MenuBarTickerSelection]
    var appearance: MenuBarTickerAppearance
    var carouselIntervalSeconds: Double

    static let storageKey = "qieman.dashboard.menuBarTickerSettings.v1"
    static let maxVisibleItemsLimit = 2
    static let minCarouselInterval: Double = 2
    static let maxCarouselInterval: Double = 30

    static let `default` = MenuBarTickerSettings(
        isEnabled: true,
        maxVisibleItems: 2,
        selections: [.kind(.overallDailyPct), .kind(.overallProfitPct), .kind(.totalValue)],
        appearance: .default,
        carouselIntervalSeconds: 5
    )

    init(
        isEnabled: Bool,
        maxVisibleItems: Int,
        selections: [MenuBarTickerSelection],
        appearance: MenuBarTickerAppearance = .default,
        carouselIntervalSeconds: Double = 5
    ) {
        self.isEnabled = isEnabled
        self.maxVisibleItems = maxVisibleItems
        self.selections = selections
        self.appearance = appearance
        self.carouselIntervalSeconds = carouselIntervalSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case maxVisibleItems
        case selections
        case enabledKinds
        case holdingSelections
        case appearance
        case carouselIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        maxVisibleItems = try container.decodeIfPresent(Int.self, forKey: .maxVisibleItems) ?? Self.default.maxVisibleItems
        appearance = try container.decodeIfPresent(MenuBarTickerAppearance.self, forKey: .appearance) ?? Self.default.appearance
        carouselIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .carouselIntervalSeconds) ?? Self.default.carouselIntervalSeconds

        if let decoded = try? container.decodeIfPresent([MenuBarTickerSelection].self, forKey: .selections) {
            selections = decoded
        } else {
            let kinds = try container.decodeIfPresent([MenuBarTickerKind].self, forKey: .enabledKinds) ?? []
            let holdings = try container.decodeIfPresent([MenuBarHoldingMetricSelection].self, forKey: .holdingSelections) ?? []
            selections = kinds.map { .kind($0) } + holdings.map { .holding($0) }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(maxVisibleItems, forKey: .maxVisibleItems)
        try container.encode(selections, forKey: .selections)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(carouselIntervalSeconds, forKey: .carouselIntervalSeconds)
    }

    static func load() -> MenuBarTickerSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(MenuBarTickerSettings.self, from: data) else {
            return .default
        }
        return decoded.normalized()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(normalized()) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func normalized() -> MenuBarTickerSettings {
        var copy = self
        copy.maxVisibleItems = min(max(copy.maxVisibleItems, 1), Self.maxVisibleItemsLimit)
        copy.carouselIntervalSeconds = min(max(copy.carouselIntervalSeconds, Self.minCarouselInterval), Self.maxCarouselInterval)
        copy.appearance = copy.appearance.normalized()

        let validKinds = Set(MenuBarTickerKind.allCases)
        var seenIDs = Set<String>()
        copy.selections = copy.selections.filter { selection in
            guard seenIDs.insert(selection.id).inserted else { return false }
            switch selection {
            case .kind(let kind): return validKinds.contains(kind)
            case .holding: return true
            }
        }
        return copy
    }
}
