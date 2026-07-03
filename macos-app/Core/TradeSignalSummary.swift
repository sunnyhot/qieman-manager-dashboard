import Foundation

enum TradeSignalAction: String, Codable, Hashable {
    case watchBuy
    case holdObserve
    case watchSell
    case waitForConfirmation
    case rebalanceReview

    var displayText: String {
        switch self {
        case .watchBuy:
            return "关注买入"
        case .holdObserve:
            return "持有观察"
        case .watchSell:
            return "关注卖出"
        case .waitForConfirmation:
            return "等待确认"
        case .rebalanceReview:
            return "再平衡复核"
        }
    }
}

enum TradeSignalStatus: String, Codable, Hashable {
    case new
    case approaching
    case triggered
    case invalidated
    case upgraded
    case staleAnalysis

    var displayText: String {
        switch self {
        case .new:
            return "新信号"
        case .approaching:
            return "接近触发"
        case .triggered:
            return "已触发"
        case .invalidated:
            return "已失效"
        case .upgraded:
            return "信号升级"
        case .staleAnalysis:
            return "基于上次分析"
        }
    }
}

struct TradeSignalItem: Identifiable, Hashable {
    let id: String
    let assetKey: String?
    let assetName: String
    let assetCode: String?
    let action: TradeSignalAction
    let status: TradeSignalStatus
    let confidence: TrendConfidence
    let title: String
    let reason: String
    let triggerSummary: String
    let invalidatingSummary: String
    let dataAsOf: String
    let analysisGeneratedAt: String
    let isBasedOnStaleAnalysis: Bool
    let priority: Int
}

struct TradeSignalSummary: Hashable {
    let headline: String
    let generatedAt: String?
    let dataAsOf: String?
    let triggeredCount: Int
    let staleAnalysis: Bool
    let items: [TradeSignalItem]

    static func make(
        report: TrendAnalysisReport?,
        rows: [PersonalAssetAggregateRow],
        settings: TradeSignalSettings,
        now: String
    ) -> TradeSignalSummary {
        guard settings.enabled, let report else {
            return TradeSignalSummary(
                headline: "等待 AI 分析",
                generatedAt: report?.generatedAt,
                dataAsOf: report?.dataAsOf,
                triggeredCount: 0,
                staleAnalysis: false,
                items: []
            )
        }

        let stale = dayString(report.generatedAt) != dayString(now)
        guard settings.useStaleAnalysis || !stale else {
            return TradeSignalSummary(
                headline: "AI 分析待更新",
                generatedAt: report.generatedAt,
                dataAsOf: report.dataAsOf,
                triggeredCount: 0,
                staleAnalysis: true,
                items: []
            )
        }

        let rowsByNameOrCode = rowLookup(rows)
        let items = report.actions.compactMap { action in
            item(
                from: action,
                report: report,
                rowsByNameOrCode: rowsByNameOrCode,
                settings: settings,
                stale: stale
            )
        }
        .sorted { left, right in
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            if left.confidence.normalizedScore != right.confidence.normalizedScore {
                return left.confidence.normalizedScore > right.confidence.normalizedScore
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }

        let headline = items.isEmpty ? "暂无 AI 操作观察" : "\(items.count) 条 AI 操作观察"
        let triggeredCount = items.filter { $0.status == .approaching || $0.status == .triggered || $0.status == .upgraded }.count
        return TradeSignalSummary(
            headline: headline,
            generatedAt: report.generatedAt,
            dataAsOf: report.dataAsOf,
            triggeredCount: triggeredCount,
            staleAnalysis: stale,
            items: items
        )
    }

    private static func item(
        from action: TrendActionCandidate,
        report: TrendAnalysisReport,
        rowsByNameOrCode: [String: PersonalAssetAggregateRow],
        settings: TradeSignalSettings,
        stale: Bool
    ) -> TradeSignalItem? {
        guard action.confidence.normalizedScore >= settings.minimumConfidence else { return nil }
        guard let mappedAction = mappedAction(for: action.kind) else { return nil }
        guard settings.allowBuySignals || mappedAction != .watchBuy else { return nil }
        guard settings.allowSellSignals || mappedAction != .watchSell else { return nil }

        let row = matchedRow(for: action, rowsByNameOrCode: rowsByNameOrCode)
        if let row, preference(for: row.key, settings: settings)?.mode == .ignore {
            return nil
        }

        let status = status(for: mappedAction, row: row, stale: stale)
        let assetName = row?.fundName ?? action.targetName ?? action.title
        let assetCode = row?.fundCode
        let stalePrefix = stale ? "基于上次 AI 分析：" : ""
        let reason = stalePrefix + action.detail
        let assetKey = row?.key
        let id = [action.id, assetKey ?? assetName, mappedAction.rawValue].joined(separator: "|")
        return TradeSignalItem(
            id: id,
            assetKey: assetKey,
            assetName: assetName,
            assetCode: assetCode,
            action: mappedAction,
            status: status,
            confidence: action.confidence,
            title: action.title,
            reason: reason,
            triggerSummary: summaryText(action.triggerConditions),
            invalidatingSummary: summaryText(action.invalidatingConditions),
            dataAsOf: report.dataAsOf,
            analysisGeneratedAt: report.generatedAt,
            isBasedOnStaleAnalysis: stale,
            priority: priority(for: mappedAction, status: status, preference: row.flatMap { preference(for: $0.key, settings: settings) })
        )
    }

    private static func mappedAction(for kind: TrendActionKind) -> TradeSignalAction? {
        switch kind {
        case .considerIncrease:
            return .watchBuy
        case .considerReduce:
            return .watchSell
        case .rebalanceReview:
            return .rebalanceReview
        case .observeInBatches:
            return .holdObserve
        case .waitForConfirmation, .watch:
            return .waitForConfirmation
        case .pausePlan:
            return .holdObserve
        }
    }

    private static func status(
        for action: TradeSignalAction,
        row: PersonalAssetAggregateRow?,
        stale: Bool
    ) -> TradeSignalStatus {
        guard let pct = row?.estimateChangePct else {
            return stale ? .staleAnalysis : .new
        }
        switch action {
        case .watchBuy where pct < 0:
            return .approaching
        case .watchSell where pct > 0:
            return .approaching
        case .rebalanceReview where abs(pct) >= 1:
            return .approaching
        default:
            return stale ? .staleAnalysis : .new
        }
    }

    private static func priority(
        for action: TradeSignalAction,
        status: TradeSignalStatus,
        preference: TradeSignalAssetPreference?
    ) -> Int {
        var value: Int
        switch status {
        case .triggered, .upgraded:
            value = 10
        case .approaching:
            value = 20
        case .invalidated:
            value = 30
        case .new:
            value = 40
        case .staleAnalysis:
            value = 50
        }
        switch action {
        case .watchBuy, .watchSell:
            value += 0
        case .rebalanceReview:
            value += 5
        case .holdObserve, .waitForConfirmation:
            value += 10
        }
        switch preference?.mode {
        case .raiseAttention:
            value -= 8
        case .lowerAttention:
            value += 8
        case .holdOnly:
            value += action == .holdObserve ? 0 : 12
        case .followGlobal, .ignore, .none:
            break
        }
        return value
    }

    private static func rowLookup(_ rows: [PersonalAssetAggregateRow]) -> [String: PersonalAssetAggregateRow] {
        var lookup: [String: PersonalAssetAggregateRow] = [:]
        for row in rows {
            lookup[row.fundName.lowercased()] = row
            lookup[row.key.lowercased()] = row
            if let code = row.fundCode {
                lookup[code.lowercased()] = row
            }
        }
        return lookup
    }

    private static func matchedRow(
        for action: TrendActionCandidate,
        rowsByNameOrCode: [String: PersonalAssetAggregateRow]
    ) -> PersonalAssetAggregateRow? {
        guard let targetName = action.targetName?.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty else {
            return nil
        }
        let key = targetName.lowercased()
        if let exact = rowsByNameOrCode[key] {
            return exact
        }
        return rowsByNameOrCode.first { element in
            key.contains(element.key) || element.key.contains(key)
        }?.value
    }

    private static func preference(for assetKey: String, settings: TradeSignalSettings) -> TradeSignalAssetPreference? {
        settings.assetPreferences.first { $0.assetKey == assetKey }
    }

    private static func summaryText(_ values: [String]) -> String {
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return trimmed.isEmpty ? "等待确认" : trimmed.prefix(2).joined(separator: "；")
    }

    private static func dayString(_ timestamp: String) -> String {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10 ? String(trimmed.prefix(10)) : trimmed
    }
}
