import AppKit
import Foundation
import SwiftUI

enum MenuBarTickerTone: String, Hashable {
    case positive
    case negative
    case neutral
}

struct MenuBarTickerEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let compactText: String
    let tone: MenuBarTickerTone
}

enum MarketIndexKind: String, Codable, CaseIterable, Identifiable {
    case sseComposite
    case csi300
    case chinext
    case hsi
    case nasdaq
    case sp500
    case dowJones

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sseComposite: return "上证指数"
        case .csi300: return "沪深300"
        case .chinext: return "创业板指"
        case .hsi: return "恒生指数"
        case .nasdaq: return "纳斯达克"
        case .sp500: return "标普500"
        case .dowJones: return "道琼斯"
        }
    }

    var compactLabel: String {
        switch self {
        case .sseComposite: return "上证"
        case .csi300: return "沪深"
        case .chinext: return "创业"
        case .hsi: return "恒指"
        case .nasdaq: return "纳指"
        case .sp500: return "标普"
        case .dowJones: return "道指"
        }
    }

    var tencentSymbol: String {
        switch self {
        case .sseComposite: return "sh000001"
        case .csi300: return "sh000300"
        case .chinext: return "sz399006"
        case .hsi: return "hkHSI"
        case .nasdaq: return "usIXIC"
        case .sp500: return "usINX"
        case .dowJones: return "usDJI"
        }
    }
}

enum MarketIndexMetric: Hashable {
    case level
    case changeAmount
    case changePct

    var labelSuffix: String {
        switch self {
        case .level: return "点位"
        case .changeAmount: return "涨跌点"
        case .changePct: return "涨跌率"
        }
    }
}

struct MarketIndexQuote: Hashable, Identifiable {
    let kind: MarketIndexKind
    let name: String
    let price: Double
    let previousClose: Double?
    let changeAmount: Double?
    let changePct: Double?
    let quotedAt: String
    let sourceLabel: String

    var id: String { kind.rawValue }
}

enum MenuBarTickerKind: String, Codable, CaseIterable, Identifiable {
    case totalValue
    case overallDailyAmount
    case overallDailyPct
    case overallProfitAmount
    case overallProfitPct
    case offExchangeDailyAmount
    case offExchangeDailyPct
    case offExchangeProfitAmount
    case offExchangeProfitPct
    case onExchangeDailyAmount
    case onExchangeDailyPct
    case onExchangeProfitAmount
    case onExchangeProfitPct
    case topDailyPct
    case topProfitPct
    case sseIndexLevel
    case sseIndexChangeAmount
    case sseIndexChangePct
    case csi300IndexLevel
    case csi300IndexChangeAmount
    case csi300IndexChangePct
    case chinextIndexLevel
    case chinextIndexChangeAmount
    case chinextIndexChangePct
    case hsiIndexLevel
    case hsiIndexChangeAmount
    case hsiIndexChangePct
    case nasdaqIndexLevel
    case nasdaqIndexChangeAmount
    case nasdaqIndexChangePct
    case sp500IndexLevel
    case sp500IndexChangeAmount
    case sp500IndexChangePct
    case dowJonesIndexLevel
    case dowJonesIndexChangeAmount
    case dowJonesIndexChangePct

    var id: String { rawValue }

    var label: String {
        if let marketIndexRequest {
            return "\(marketIndexRequest.kind.compactLabel)\(marketIndexRequest.metric.labelSuffix)"
        }

        switch self {
        case .totalValue: return "总资产"
        case .overallDailyAmount: return "整体涨跌额"
        case .overallDailyPct: return "整体涨跌率"
        case .overallProfitAmount: return "整体收益额"
        case .overallProfitPct: return "整体收益率"
        case .offExchangeDailyAmount: return "场外涨跌额"
        case .offExchangeDailyPct: return "场外涨跌率"
        case .offExchangeProfitAmount: return "场外收益额"
        case .offExchangeProfitPct: return "场外收益率"
        case .onExchangeDailyAmount: return "场内涨跌额"
        case .onExchangeDailyPct: return "场内涨跌率"
        case .onExchangeProfitAmount: return "场内收益额"
        case .onExchangeProfitPct: return "场内收益率"
        case .topDailyPct: return "最大涨跌标的"
        case .topProfitPct: return "最大收益标的"
        default: return rawValue
        }
    }

    var detail: String {
        if let marketIndexRequest {
            switch marketIndexRequest.metric {
            case .level:
                return "\(marketIndexRequest.kind.label)实时点位"
            case .changeAmount, .changePct:
                return "\(marketIndexRequest.kind.label)当日涨跌"
            }
        }

        switch self {
        case .totalValue:
            return "总持仓 + 待确认 + 下次计划"
        case .overallDailyAmount, .overallDailyPct:
            return "全部已持有资产今日涨跌"
        case .overallProfitAmount, .overallProfitPct:
            return "全部已持有资产相对成本收益"
        case .offExchangeDailyAmount, .offExchangeDailyPct, .offExchangeProfitAmount, .offExchangeProfitPct:
            return "按场外基金聚合"
        case .onExchangeDailyAmount, .onExchangeDailyPct, .onExchangeProfitAmount, .onExchangeProfitPct:
            return "按场内基金、ETF、LOF 聚合"
        case .topDailyPct:
            return "自动选择今日涨跌绝对值最大的持仓"
        case .topProfitPct:
            return "自动选择收益率最高的持仓"
        default:
            return "大盘指数行情"
        }
    }

    var marketIndexRequest: (kind: MarketIndexKind, metric: MarketIndexMetric)? {
        switch self {
        case .sseIndexLevel: return (.sseComposite, .level)
        case .sseIndexChangeAmount: return (.sseComposite, .changeAmount)
        case .sseIndexChangePct: return (.sseComposite, .changePct)
        case .csi300IndexLevel: return (.csi300, .level)
        case .csi300IndexChangeAmount: return (.csi300, .changeAmount)
        case .csi300IndexChangePct: return (.csi300, .changePct)
        case .chinextIndexLevel: return (.chinext, .level)
        case .chinextIndexChangeAmount: return (.chinext, .changeAmount)
        case .chinextIndexChangePct: return (.chinext, .changePct)
        case .hsiIndexLevel: return (.hsi, .level)
        case .hsiIndexChangeAmount: return (.hsi, .changeAmount)
        case .hsiIndexChangePct: return (.hsi, .changePct)
        case .nasdaqIndexLevel: return (.nasdaq, .level)
        case .nasdaqIndexChangeAmount: return (.nasdaq, .changeAmount)
        case .nasdaqIndexChangePct: return (.nasdaq, .changePct)
        case .sp500IndexLevel: return (.sp500, .level)
        case .sp500IndexChangeAmount: return (.sp500, .changeAmount)
        case .sp500IndexChangePct: return (.sp500, .changePct)
        case .dowJonesIndexLevel: return (.dowJones, .level)
        case .dowJonesIndexChangeAmount: return (.dowJones, .changeAmount)
        case .dowJonesIndexChangePct: return (.dowJones, .changePct)
        default: return nil
        }
    }

    static let overallKinds: [MenuBarTickerKind] = [
        .totalValue,
        .overallDailyAmount,
        .overallDailyPct,
        .overallProfitAmount,
        .overallProfitPct,
    ]

    static let fundMarketKinds: [MenuBarTickerKind] = [
        .offExchangeDailyAmount,
        .offExchangeDailyPct,
        .offExchangeProfitAmount,
        .offExchangeProfitPct,
        .onExchangeDailyAmount,
        .onExchangeDailyPct,
        .onExchangeProfitAmount,
        .onExchangeProfitPct,
    ]

    static let marketIndexKinds: [MenuBarTickerKind] = [
        .sseIndexChangePct,
        .sseIndexChangeAmount,
        .sseIndexLevel,
        .csi300IndexChangePct,
        .csi300IndexChangeAmount,
        .csi300IndexLevel,
        .chinextIndexChangePct,
        .chinextIndexChangeAmount,
        .chinextIndexLevel,
        .hsiIndexChangePct,
        .hsiIndexChangeAmount,
        .hsiIndexLevel,
        .nasdaqIndexChangePct,
        .nasdaqIndexChangeAmount,
        .nasdaqIndexLevel,
        .sp500IndexChangePct,
        .sp500IndexChangeAmount,
        .sp500IndexLevel,
        .dowJonesIndexChangePct,
        .dowJonesIndexChangeAmount,
        .dowJonesIndexLevel,
    ]

    static let aShareIndexKinds: [MenuBarTickerKind] = [
        .sseIndexChangePct, .sseIndexChangeAmount, .sseIndexLevel,
        .csi300IndexChangePct, .csi300IndexChangeAmount, .csi300IndexLevel,
        .chinextIndexChangePct, .chinextIndexChangeAmount, .chinextIndexLevel,
    ]

    static let hkIndexKinds: [MenuBarTickerKind] = [
        .hsiIndexChangePct, .hsiIndexChangeAmount, .hsiIndexLevel,
    ]

    static let usIndexKinds: [MenuBarTickerKind] = [
        .nasdaqIndexChangePct, .nasdaqIndexChangeAmount, .nasdaqIndexLevel,
        .sp500IndexChangePct, .sp500IndexChangeAmount, .sp500IndexLevel,
        .dowJonesIndexChangePct, .dowJonesIndexChangeAmount, .dowJonesIndexLevel,
    ]

    static func tickerKind(indexKind: MarketIndexKind, metric: MarketIndexMetric) -> MenuBarTickerKind? {
        switch (indexKind, metric) {
        case (.sseComposite, .level): return .sseIndexLevel
        case (.sseComposite, .changeAmount): return .sseIndexChangeAmount
        case (.sseComposite, .changePct): return .sseIndexChangePct
        case (.csi300, .level): return .csi300IndexLevel
        case (.csi300, .changeAmount): return .csi300IndexChangeAmount
        case (.csi300, .changePct): return .csi300IndexChangePct
        case (.chinext, .level): return .chinextIndexLevel
        case (.chinext, .changeAmount): return .chinextIndexChangeAmount
        case (.chinext, .changePct): return .chinextIndexChangePct
        case (.hsi, .level): return .hsiIndexLevel
        case (.hsi, .changeAmount): return .hsiIndexChangeAmount
        case (.hsi, .changePct): return .hsiIndexChangePct
        case (.nasdaq, .level): return .nasdaqIndexLevel
        case (.nasdaq, .changeAmount): return .nasdaqIndexChangeAmount
        case (.nasdaq, .changePct): return .nasdaqIndexChangePct
        case (.sp500, .level): return .sp500IndexLevel
        case (.sp500, .changeAmount): return .sp500IndexChangeAmount
        case (.sp500, .changePct): return .sp500IndexChangePct
        case (.dowJones, .level): return .dowJonesIndexLevel
        case (.dowJones, .changeAmount): return .dowJonesIndexChangeAmount
        case (.dowJones, .changePct): return .dowJonesIndexChangePct
        }
    }

    static let automaticKinds: [MenuBarTickerKind] = [
        .topDailyPct,
        .topProfitPct,
    ]
}

enum MenuBarHoldingMetric: String, Codable, CaseIterable, Identifiable {
    case dailyAmount
    case dailyPct
    case profitAmount
    case profitPct
    case price
    case marketValue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dailyAmount: return "涨跌额"
        case .dailyPct: return "涨跌率"
        case .profitAmount: return "收益额"
        case .profitPct: return "收益率"
        case .price: return "现价"
        case .marketValue: return "市值"
        }
    }
}

struct MenuBarHoldingMetricSelection: Codable, Hashable, Identifiable {
    var holdingID: UUID
    var metric: MenuBarHoldingMetric

    var id: String { "\(holdingID.uuidString):\(metric.rawValue)" }
}

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

struct MenuBarTickerAppearance: Codable, Hashable {
    var textColorMode: MenuBarTickerTextColorMode
    var customTextColorHex: String
    var fontSize: Double
    var isBold: Bool
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
        spacingMode: .automatic,
        manualSpacing: 10,
        widthMode: .automatic,
        manualWidth: 180
    )

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
    var enabledKinds: [MenuBarTickerKind]
    var holdingSelections: [MenuBarHoldingMetricSelection]
    var appearance: MenuBarTickerAppearance

    static let storageKey = "qieman.dashboard.menuBarTickerSettings.v1"
    static let maxVisibleItemsLimit = 2

    static let `default` = MenuBarTickerSettings(
        isEnabled: true,
        maxVisibleItems: 2,
        enabledKinds: [.overallDailyPct, .overallProfitPct, .totalValue],
        holdingSelections: [],
        appearance: .default
    )

    init(
        isEnabled: Bool,
        maxVisibleItems: Int,
        enabledKinds: [MenuBarTickerKind],
        holdingSelections: [MenuBarHoldingMetricSelection],
        appearance: MenuBarTickerAppearance = .default
    ) {
        self.isEnabled = isEnabled
        self.maxVisibleItems = maxVisibleItems
        self.enabledKinds = enabledKinds
        self.holdingSelections = holdingSelections
        self.appearance = appearance
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case maxVisibleItems
        case enabledKinds
        case holdingSelections
        case appearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        maxVisibleItems = try container.decodeIfPresent(Int.self, forKey: .maxVisibleItems) ?? Self.default.maxVisibleItems
        enabledKinds = try container.decodeIfPresent([MenuBarTickerKind].self, forKey: .enabledKinds) ?? Self.default.enabledKinds
        holdingSelections = try container.decodeIfPresent([MenuBarHoldingMetricSelection].self, forKey: .holdingSelections) ?? Self.default.holdingSelections
        appearance = try container.decodeIfPresent(MenuBarTickerAppearance.self, forKey: .appearance) ?? Self.default.appearance
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(maxVisibleItems, forKey: .maxVisibleItems)
        try container.encode(enabledKinds, forKey: .enabledKinds)
        try container.encode(holdingSelections, forKey: .holdingSelections)
        try container.encode(appearance, forKey: .appearance)
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
        copy.appearance = copy.appearance.normalized()

        // Remove kinds that no longer exist in the enum
        let validKinds = Set(MenuBarTickerKind.allCases)
        copy.enabledKinds = copy.enabledKinds.filter { validKinds.contains($0) }

        var seenKinds = Set<MenuBarTickerKind>()
        copy.enabledKinds = copy.enabledKinds.filter { seenKinds.insert($0).inserted }

        var seenSelections = Set<String>()
        copy.holdingSelections = copy.holdingSelections.filter { selection in
            seenSelections.insert(selection.id).inserted
        }
        return copy
    }
}

extension AppModel {
    var menuBarTickerConfiguredItemCount: Int {
        menuBarTickerSettings.enabledKinds.count + menuBarTickerSettings.holdingSelections.count
    }

    var menuBarTickerVisibleEntries: [MenuBarTickerEntry] {
        guard menuBarTickerSettings.isEnabled else { return [] }
        let settings = menuBarTickerSettings.normalized()
        let entries = menuBarTickerCandidateEntries(settings: settings)
        return Array(entries.prefix(settings.maxVisibleItems))
    }

    var menuBarTickerTitle: String? {
        let text = menuBarTickerVisibleEntries
            .map(\.compactText)
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
        return text.isEmpty ? nil : text
    }

    func isMenuBarTickerKindEnabled(_ kind: MenuBarTickerKind) -> Bool {
        menuBarTickerSettings.enabledKinds.contains(kind)
    }

    func setMenuBarTickerKind(_ kind: MenuBarTickerKind, isEnabled: Bool) {
        var settings = menuBarTickerSettings
        if isEnabled {
            if !settings.enabledKinds.contains(kind) {
                let totalSelected = settings.enabledKinds.count + settings.holdingSelections.count
                if totalSelected >= settings.maxVisibleItems {
                    // Remove the oldest enabled kind to make room
                    settings.enabledKinds.removeFirst()
                }
                settings.enabledKinds.append(kind)
            }
        } else {
            settings.enabledKinds.removeAll { $0 == kind }
        }
        persistMenuBarTickerSettings(settings)
        if isEnabled, kind.marketIndexRequest != nil {
            Task { await refreshMarketIndices(kinds: MarketIndexKind.allCases, updateNotice: false) }
        }
    }

    var isMenuBarTickerSelectionFull: Bool {
        let total = menuBarTickerSettings.enabledKinds.count + menuBarTickerSettings.holdingSelections.count
        return total >= menuBarTickerSettings.maxVisibleItems
    }

    func isMenuBarHoldingMetricEnabled(holdingID: UUID, metric: MenuBarHoldingMetric) -> Bool {
        menuBarTickerSettings.holdingSelections.contains {
            $0.holdingID == holdingID && $0.metric == metric
        }
    }

    func setMenuBarHoldingMetric(holdingID: UUID, metric: MenuBarHoldingMetric, isEnabled: Bool) {
        var settings = menuBarTickerSettings
        if isEnabled {
            let selection = MenuBarHoldingMetricSelection(holdingID: holdingID, metric: metric)
            if !settings.holdingSelections.contains(selection) {
                let totalSelected = settings.enabledKinds.count + settings.holdingSelections.count
                if totalSelected >= settings.maxVisibleItems {
                    // Remove the oldest holding selection to make room
                    if settings.holdingSelections.isEmpty {
                        settings.enabledKinds.removeFirst()
                    } else {
                        settings.holdingSelections.removeFirst()
                    }
                }
                settings.holdingSelections.append(selection)
            }
        } else {
            settings.holdingSelections.removeAll {
                $0.holdingID == holdingID && $0.metric == metric
            }
        }
        persistMenuBarTickerSettings(settings)
    }

    func setMenuBarTickerEnabled(_ isEnabled: Bool) {
        var settings = menuBarTickerSettings
        settings.isEnabled = isEnabled
        persistMenuBarTickerSettings(settings)
        if isEnabled {
            Task { await refreshMarketIndicesIfNeeded() }
        }
    }

    func setMenuBarTickerMaxVisibleItems(_ maxVisibleItems: Int) {
        var settings = menuBarTickerSettings
        settings.maxVisibleItems = maxVisibleItems
        persistMenuBarTickerSettings(settings)
    }

    func updateMenuBarTickerAppearance(_ update: (inout MenuBarTickerAppearance) -> Void) {
        var settings = menuBarTickerSettings
        update(&settings.appearance)
        persistMenuBarTickerSettings(settings)
    }

    func resetMenuBarTickerSettings() {
        persistMenuBarTickerSettings(.default)
    }

    func clearMenuBarHoldingSelections() {
        var settings = menuBarTickerSettings
        settings.holdingSelections.removeAll()
        persistMenuBarTickerSettings(settings)
    }

    private func persistMenuBarTickerSettings(_ settings: MenuBarTickerSettings) {
        let normalized = settings.normalized()
        menuBarTickerSettings = normalized
        normalized.save()
    }

    private func menuBarTickerCandidateEntries(settings: MenuBarTickerSettings) -> [MenuBarTickerEntry] {
        var entries: [MenuBarTickerEntry] = []
        let rows = userPortfolioSnapshot?.rows ?? []
        let aggregates = MenuBarTickerAggregateSet(rows: rows)
        let rowsByHoldingID = Dictionary(rows.map { ($0.holding.id, $0) }, uniquingKeysWith: { first, _ in first })

        for kind in settings.enabledKinds {
            if let entry = menuBarTickerEntry(for: kind, rows: rows, aggregates: aggregates) {
                entries.append(entry)
            }
        }

        for selection in settings.holdingSelections {
            guard let row = rowsByHoldingID[selection.holdingID],
                  let entry = menuBarTickerEntry(row: row, metric: selection.metric) else {
                continue
            }
            entries.append(entry)
        }

        return entries
    }

    private func menuBarTickerEntry(
        for kind: MenuBarTickerKind,
        rows: [UserPortfolioValuationRow],
        aggregates: MenuBarTickerAggregateSet
    ) -> MenuBarTickerEntry? {
        switch kind {
        case .totalValue:
            guard let summary = personalAssetSummary else { return nil }
            let value = summary.totalEffectiveHoldingAmount
            guard value > 0 else { return nil }
            return MenuBarTickerEntry(
                id: kind.rawValue,
                title: "总资产",
                value: compactCurrency(value),
                detail: currencyText(value),
                compactText: "总 \(compactCurrency(value))",
                tone: .neutral
            )
        case .overallDailyAmount:
            return aggregates.all.amountEntry(id: kind.rawValue, title: "整体涨跌", compactTitle: "今", value: aggregates.all.dailyAmount)
        case .overallDailyPct:
            return aggregates.all.percentEntry(id: kind.rawValue, title: "整体涨跌率", compactTitle: "今", value: aggregates.all.dailyPct)
        case .overallProfitAmount:
            return aggregates.all.amountEntry(id: kind.rawValue, title: "整体收益", compactTitle: "益", value: aggregates.all.profitAmount)
        case .overallProfitPct:
            return aggregates.all.percentEntry(id: kind.rawValue, title: "整体收益率", compactTitle: "益", value: aggregates.all.profitPct)
        case .offExchangeDailyAmount:
            let aggregate = aggregates.fund(.offExchange)
            return aggregate.amountEntry(id: kind.rawValue, title: "场外涨跌", compactTitle: "场外", value: aggregate.dailyAmount)
        case .offExchangeDailyPct:
            let aggregate = aggregates.fund(.offExchange)
            return aggregate.percentEntry(id: kind.rawValue, title: "场外涨跌率", compactTitle: "场外", value: aggregate.dailyPct)
        case .offExchangeProfitAmount:
            let aggregate = aggregates.fund(.offExchange)
            return aggregate.amountEntry(id: kind.rawValue, title: "场外收益", compactTitle: "场外益", value: aggregate.profitAmount)
        case .offExchangeProfitPct:
            let aggregate = aggregates.fund(.offExchange)
            return aggregate.percentEntry(id: kind.rawValue, title: "场外收益率", compactTitle: "场外益", value: aggregate.profitPct)
        case .onExchangeDailyAmount:
            let aggregate = aggregates.fund(.onExchange)
            return aggregate.amountEntry(id: kind.rawValue, title: "场内涨跌", compactTitle: "场内", value: aggregate.dailyAmount)
        case .onExchangeDailyPct:
            let aggregate = aggregates.fund(.onExchange)
            return aggregate.percentEntry(id: kind.rawValue, title: "场内涨跌率", compactTitle: "场内", value: aggregate.dailyPct)
        case .onExchangeProfitAmount:
            let aggregate = aggregates.fund(.onExchange)
            return aggregate.amountEntry(id: kind.rawValue, title: "场内收益", compactTitle: "场内益", value: aggregate.profitAmount)
        case .onExchangeProfitPct:
            let aggregate = aggregates.fund(.onExchange)
            return aggregate.percentEntry(id: kind.rawValue, title: "场内收益率", compactTitle: "场内益", value: aggregate.profitPct)
        case .sseIndexLevel, .sseIndexChangeAmount, .sseIndexChangePct,
             .csi300IndexLevel, .csi300IndexChangeAmount, .csi300IndexChangePct,
             .chinextIndexLevel, .chinextIndexChangeAmount, .chinextIndexChangePct,
             .hsiIndexLevel, .hsiIndexChangeAmount, .hsiIndexChangePct,
             .nasdaqIndexLevel, .nasdaqIndexChangeAmount, .nasdaqIndexChangePct,
             .sp500IndexLevel, .sp500IndexChangeAmount, .sp500IndexChangePct,
             .dowJonesIndexLevel, .dowJonesIndexChangeAmount, .dowJonesIndexChangePct:
            guard let request = kind.marketIndexRequest else { return nil }
            return menuBarTickerEntry(indexKind: request.kind, metric: request.metric, id: kind.rawValue)
        case .topDailyPct:
            guard let row = rows
                .filter({ $0.estimateChangePct != nil || $0.estimatedDailyChangeAmount != nil })
                .max(by: { abs($0.estimateChangePct ?? 0) < abs($1.estimateChangePct ?? 0) }) else {
                return nil
            }
            return menuBarTickerEntry(row: row, metric: .dailyPct, customTitle: "最大涨跌")
        case .topProfitPct:
            guard let row = rows
                .filter({ $0.profitPct != nil || $0.profitAmount != nil })
                .max(by: { ($0.profitPct ?? -.greatestFiniteMagnitude) < ($1.profitPct ?? -.greatestFiniteMagnitude) }) else {
                return nil
            }
            return menuBarTickerEntry(row: row, metric: .profitPct, customTitle: "最大收益")
        }
    }

    private func menuBarTickerEntry(indexKind: MarketIndexKind, metric: MarketIndexMetric, id: String) -> MenuBarTickerEntry? {
        guard let quote = marketIndexQuotes[indexKind] else { return nil }
        switch metric {
        case .level:
            let text = compactIndexLevel(quote.price)
            return MenuBarTickerEntry(
                id: id,
                title: "\(indexKind.compactLabel)点位",
                value: text,
                detail: "\(quote.name) · \(quote.sourceLabel)\(quote.quotedAt.isEmpty ? "" : " · \(quote.quotedAt)")",
                compactText: "\(indexKind.compactLabel) \(text)",
                tone: .neutral
            )
        case .changeAmount:
            guard let value = quote.changeAmount else { return nil }
            let text = compactIndexPoints(value)
            return MenuBarTickerEntry(
                id: id,
                title: "\(indexKind.compactLabel)涨跌点",
                value: text,
                detail: "\(quote.name) · \(quote.changePct.map(compactPercent) ?? "暂无涨跌率")",
                compactText: "\(indexKind.compactLabel) \(text)",
                tone: tone(for: value)
            )
        case .changePct:
            guard let value = quote.changePct else { return nil }
            let text = compactPercent(value)
            return MenuBarTickerEntry(
                id: id,
                title: "\(indexKind.compactLabel)涨跌率",
                value: text,
                detail: "\(quote.name) · \(quote.changeAmount.map(compactIndexPoints) ?? "暂无涨跌点")",
                compactText: "\(indexKind.compactLabel) \(text)",
                tone: tone(for: value)
            )
        }
    }

    private func menuBarTickerEntry(
        row: UserPortfolioValuationRow,
        metric: MenuBarHoldingMetric,
        customTitle: String? = nil
    ) -> MenuBarTickerEntry? {
        let name = compactAssetName(row.fundName)
        let title = customTitle ?? name
        let id = "holding:\(row.holding.id.uuidString):\(metric.rawValue)"

        switch metric {
        case .dailyAmount:
            guard let value = row.estimatedDailyChangeAmount else { return nil }
            let text = compactSignedCurrency(value, market: row.holding.detectedMarket)
            return MenuBarTickerEntry(
                id: id,
                title: "\(title)涨跌",
                value: text,
                detail: "\(row.fundName) · \(signedCurrencyText(value, market: row.holding.detectedMarket))",
                compactText: "\(name) \(text)",
                tone: tone(for: value)
            )
        case .dailyPct:
            guard let value = row.estimateChangePct ?? pctFromAmount(row.estimatedDailyChangeAmount, previous: row.previousMarketValue) else { return nil }
            let text = compactPercent(value)
            return MenuBarTickerEntry(
                id: id,
                title: "\(title)涨跌率",
                value: text,
                detail: "\(row.fundName) · \(signedCurrencyText(row.estimatedDailyChangeAmount, market: row.holding.detectedMarket))",
                compactText: "\(name) \(text)",
                tone: tone(for: value)
            )
        case .profitAmount:
            guard let value = row.profitAmount else { return nil }
            let text = compactSignedCurrency(value, market: row.holding.detectedMarket)
            return MenuBarTickerEntry(
                id: id,
                title: "\(title)收益",
                value: text,
                detail: "\(row.fundName) · \(percentOptional(row.profitPct))",
                compactText: "\(name)益 \(text)",
                tone: tone(for: value)
            )
        case .profitPct:
            guard let value = row.profitPct else { return nil }
            let text = compactPercent(value)
            return MenuBarTickerEntry(
                id: id,
                title: "\(title)收益率",
                value: text,
                detail: "\(row.fundName) · \(signedCurrencyText(row.profitAmount, market: row.holding.detectedMarket))",
                compactText: "\(name)益 \(text)",
                tone: tone(for: value)
            )
        case .price:
            guard let value = row.resolvedPrice else { return nil }
            let text = decimalText(value)
            return MenuBarTickerEntry(
                id: id,
                title: "\(title)现价",
                value: text,
                detail: "\(row.fundName) · \(row.resolvedPriceSource ?? "当前价格")",
                compactText: "\(name) \(text)",
                tone: .neutral
            )
        case .marketValue:
            guard let value = row.marketValue else { return nil }
            let text = compactCurrency(value, market: row.holding.detectedMarket)
            return MenuBarTickerEntry(
                id: id,
                title: "\(title)市值",
                value: text,
                detail: "\(row.fundName) · \(currencyText(value, market: row.holding.detectedMarket))",
                compactText: "\(name) \(text)",
                tone: .neutral
            )
        }
    }

}

private struct MenuBarTickerAggregateSet {
    let all: MenuBarTickerAggregate
    private let markets: [StockMarket: MenuBarTickerAggregate]
    private let funds: [FundMarket: MenuBarTickerAggregate]

    init(rows: [UserPortfolioValuationRow]) {
        var stockRowsByMarket: [StockMarket: [UserPortfolioValuationRow]] = [:]
        var fundRowsByMarket: [FundMarket: [UserPortfolioValuationRow]] = [:]

        for row in rows {
            if row.holding.assetType == .stock, let market = row.holding.detectedMarket {
                stockRowsByMarket[market, default: []].append(row)
            } else if row.holding.assetType == .fund, let market = row.holding.detectedFundMarket {
                fundRowsByMarket[market, default: []].append(row)
            }
        }

        all = MenuBarTickerAggregate(rows: rows)
        markets = Dictionary(uniqueKeysWithValues: StockMarket.allCases.map { market in
            (market, MenuBarTickerAggregate(rows: stockRowsByMarket[market] ?? []))
        })
        funds = Dictionary(uniqueKeysWithValues: FundMarket.allCases.map { market in
            (market, MenuBarTickerAggregate(rows: fundRowsByMarket[market] ?? []))
        })
    }

    func market(_ market: StockMarket) -> MenuBarTickerAggregate {
        markets[market] ?? .empty
    }

    func fund(_ market: FundMarket) -> MenuBarTickerAggregate {
        funds[market] ?? .empty
    }
}

private struct MenuBarTickerAggregate {
    static let empty = MenuBarTickerAggregate(rows: [])

    let dailyAmount: Double?
    let previousValue: Double?
    let dailyPct: Double?
    let profitAmount: Double?
    let costValue: Double?
    let profitPct: Double?

    init(rows: [UserPortfolioValuationRow]) {
        let dailyAmounts = rows.compactMap(\.estimatedDailyChangeAmount)
        let previousValues = rows.compactMap(\.previousMarketValue)
        let profitAmounts = rows.compactMap(\.profitAmount)
        let costValues = rows.compactMap(\.costValue)

        dailyAmount = compactNilIfEmpty(dailyAmounts.reduce(0, +), sourceCount: dailyAmounts.count)
        previousValue = compactNilIfEmpty(previousValues.reduce(0, +), sourceCount: previousValues.count)
        dailyPct = pctFromAmount(dailyAmount, previous: previousValue)
        profitAmount = compactNilIfEmpty(profitAmounts.reduce(0, +), sourceCount: profitAmounts.count)
        costValue = compactNilIfEmpty(costValues.reduce(0, +), sourceCount: costValues.count)
        profitPct = pctFromAmount(profitAmount, previous: costValue)
    }

    func amountEntry(id: String, title: String, compactTitle: String, value: Double?, market: StockMarket? = nil) -> MenuBarTickerEntry? {
        guard let value else { return nil }
        let text = compactSignedCurrency(value, market: market)
        return MenuBarTickerEntry(
            id: id,
            title: title,
            value: text,
            detail: signedCurrencyText(value, market: market),
            compactText: "\(compactTitle) \(text)",
            tone: tone(for: value)
        )
    }

    func percentEntry(id: String, title: String, compactTitle: String, value: Double?) -> MenuBarTickerEntry? {
        guard let value else { return nil }
        let text = compactPercent(value)
        return MenuBarTickerEntry(
            id: id,
            title: title,
            value: text,
            detail: text,
            compactText: "\(compactTitle) \(text)",
            tone: tone(for: value)
        )
    }
}

private func compactNilIfEmpty(_ value: Double, sourceCount: Int) -> Double? {
    sourceCount > 0 ? value : nil
}

private func pctFromAmount(_ amount: Double?, previous: Double?) -> Double? {
    guard let amount, let previous, previous > 0 else { return nil }
    return amount / previous * 100
}

private func tone(for value: Double?) -> MenuBarTickerTone {
    let value = value ?? 0
    if value > 0 { return .positive }
    if value < 0 { return .negative }
    return .neutral
}

private func compactCurrency(_ value: Double, market: StockMarket? = nil) -> String {
    compactCurrencyText(value, market: market, signed: false)
}

private func compactSignedCurrency(_ value: Double, market: StockMarket? = nil) -> String {
    compactCurrencyText(value, market: market, signed: true)
}

private func compactCurrencyText(_ value: Double, market: StockMarket?, signed: Bool) -> String {
    let symbol = market?.currencySymbol ?? "¥"
    let sign = signed ? (value >= 0 ? "+" : "-") : ""
    let absolute = abs(value)
    if absolute >= 100_000_000 {
        return "\(symbol)\(sign)\(String(format: "%.1f", absolute / 100_000_000))亿"
    }
    if absolute >= 10_000 {
        return "\(symbol)\(sign)\(String(format: "%.1f", absolute / 10_000))万"
    }
    if absolute >= 1_000 {
        return "\(symbol)\(sign)\(String(format: "%.0f", absolute))"
    }
    return "\(symbol)\(sign)\(String(format: "%.2f", absolute))"
}

private func compactPercent(_ value: Double) -> String {
    String(format: "%+.2f%%", value)
}

private func compactIndexLevel(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private func compactIndexPoints(_ value: Double) -> String {
    String(format: "%+.2f点", value)
}

private func compactAssetName(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "标的" }
    let cleaned = trimmed
        .replacingOccurrences(of: "指数证券投资基金", with: "")
        .replacingOccurrences(of: "证券投资基金", with: "")
        .replacingOccurrences(of: "交易型开放式指数", with: "ETF")
        .replacingOccurrences(of: "(QDII)", with: "")
        .replacingOccurrences(of: "（QDII）", with: "")
    if cleaned.count <= 6 { return cleaned }
    return String(cleaned.prefix(6))
}
