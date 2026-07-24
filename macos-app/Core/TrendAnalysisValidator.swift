import Foundation

struct TrendValidationResult: Hashable {
    let isValid: Bool
    let messages: [String]

    static let valid = TrendValidationResult(isValid: true, messages: [])
}

struct TrendAnalysisValidator {
    private let requiredHorizons = Set(TrendHorizon.allCases)
    private let forbiddenTerms = [
        "必须买入",
        "必须卖出",
        "一定上涨",
        "一定卖出",
        "保证上涨",
        "保证收益"
    ]

    func validate(_ report: TrendAnalysisReport, expectedFundCodes: [String] = [], expectedPrivacyMode: TrendPrivacyMode? = nil) -> TrendValidationResult {
        var messages: [String] = []

        let horizonKinds = Set(report.horizons.map(\.horizon))
        if report.horizons.count != requiredHorizons.count || horizonKinds != requiredHorizons {
            messages.append("短中长期趋势必须完整包含 short/medium/long 且各出现一次。")
        }
        for horizon in report.horizons where horizon.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("短中长期趋势缺少 rationale/判断依据：\(horizon.horizon.rawValue)")
        }
        for horizon in report.horizons where horizon.counterSignals.isEmpty {
            messages.append("短中长期趋势缺少 counterSignals/反证条件：\(horizon.horizon.rawValue)")
        }
        if !report.disclaimer.contains("非投资建议") {
            messages.append("缺少明确的非投资建议声明。")
        }
        let hasTavilyEvidence = report.evidence.contains { $0.id.hasPrefix("web:tavily:") }
        if report.externalSignalStatus == .available && !hasTavilyEvidence {
            messages.append("externalSignalStatus 为 available 时必须引用本次 Tavily 搜索产生的 web:tavily:* 证据。")
        }
        if report.externalSignalStatus != .available && hasTavilyEvidence {
            messages.append("报告已经引用 Tavily 网页证据，externalSignalStatus 应为 available。")
        }

        // 证据账本解析：sectors/marketOutlook/opportunities 引用的 evidenceID 必须都在 report.evidence 中。
        let evidenceIDs = Set(report.evidence.map(\.id))
        for id in collectReferencedEvidenceIDs(report) where !evidenceIDs.contains(id) {
            messages.append("引用的证据 ID 不存在：\(id)")
        }

        // confidence 分数范围 0...100。
        for confidence in collectConfidenceScores(report) where confidence.score < 0 || confidence.score > 100 {
            messages.append("confidence score 必须在 0...100 之间：\(confidence.score)")
        }

        // privacyMode 必须与本次分析快照一致（App 在 submit 阶段已覆盖，这里做防御性校验）。
        if let expectedPrivacyMode, report.privacyMode != expectedPrivacyMode {
            messages.append("privacyMode 必须与本次分析快照一致（\(expectedPrivacyMode.rawValue)）。")
        }

        for sector in report.sectors {
            if sector.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append("板块缺少 rationale/判断依据：\(sector.name)")
            }
            if sector.counterSignals.isEmpty {
                messages.append("板块缺少 counterSignals/反证条件：\(sector.name)")
            }
        }

        for market in report.marketOutlook {
            if market.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append("大盘/大类资产缺少 rationale/判断依据：\(market.name)")
            }
            if market.counterSignals.isEmpty {
                messages.append("大盘/大类资产缺少 counterSignals/反证条件：\(market.name)")
            }
        }

        for opportunity in report.opportunities {
            if opportunity.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append("投资机会缺少 rationale/判断依据：\(opportunity.name)")
            }
            if opportunity.triggerConditions.isEmpty {
                messages.append("投资机会缺少 triggerConditions/触发条件：\(opportunity.name)")
            }
            if opportunity.invalidatingConditions.isEmpty {
                messages.append("投资机会缺少 invalidatingConditions/反证条件：\(opportunity.name)")
            }
            if opportunity.counterSignals.isEmpty {
                messages.append("投资机会缺少 counterSignals/反向信号：\(opportunity.name)")
            }
        }

        for asset in report.keyAssets {
            validate(asset: asset, label: "关键资产", messages: &messages)
        }

        for asset in report.assetTrends {
            validate(asset: asset, label: "已持有基金趋势", messages: &messages)
        }

        let reportedFundCodes = Set(report.assetTrends.compactMap { normalizedCode($0.code) })
        for code in Set(expectedFundCodes.compactMap(normalizedCode)).sorted() where !reportedFundCodes.contains(code) {
            messages.append("已持有基金缺少 assetTrends 趋势分析：\(code)")
        }

        for action in report.actions {
            if action.triggerConditions.isEmpty {
                messages.append("行动候选缺少 trigger/触发条件：\(action.title)")
            }
            if action.invalidatingConditions.isEmpty {
                messages.append("行动候选缺少 invalidating/反证条件：\(action.title)")
            }
        }

        let portfolioParts = [report.portfolio.headline, report.portfolio.summary, report.disclaimer]
        let actionParts = report.actions.flatMap { [$0.title, $0.detail] }
        let horizonParts = report.horizons.flatMap { [$0.rationale] + $0.counterSignals }
        let sectorParts = report.sectors.flatMap { [$0.rationale] + $0.counterSignals }
        let marketParts = report.marketOutlook.flatMap { [$0.rationale] + $0.counterSignals }
        let opportunityParts = report.opportunities.flatMap {
            [$0.rationale] + $0.triggerConditions + $0.invalidatingConditions + $0.counterSignals
        }
        let assetParts = (report.keyAssets + report.assetTrends).flatMap { [$0.impactText, $0.rationale] + $0.counterSignals }
        let searchableParts = portfolioParts + actionParts + horizonParts + sectorParts + marketParts + opportunityParts + assetParts
        let searchableText = searchableParts.joined(separator: "\n")
        for term in forbiddenTerms where searchableText.contains(term) {
            messages.append("包含强制或 absolute 表述：\(term)")
        }

        return messages.isEmpty ? .valid : TrendValidationResult(isValid: false, messages: messages)
    }

    private func validate(asset: TrendAssetView, label: String, messages: inout [String]) {
            if asset.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append("\(label)缺少 rationale/判断依据：\(asset.name)")
            }
            if asset.counterSignals.isEmpty {
                messages.append("\(label)缺少 counterSignals/反证条件：\(asset.name)")
            }
            for horizon in asset.horizons {
                if horizon.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages.append("\(label)周期缺少 rationale/判断依据：\(asset.name) \(horizon.horizon.rawValue)")
                }
                if horizon.counterSignals.isEmpty {
                    messages.append("\(label)周期缺少 counterSignals/反证条件：\(asset.name) \(horizon.horizon.rawValue)")
                }
            }
    }

    private func normalizedCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.uppercased().filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? nil : normalized
    }

    /// sectors/marketOutlook/opportunities 中引用的全部 evidenceID（去重、保序）。
    private func collectReferencedEvidenceIDs(_ report: TrendAnalysisReport) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        let append: (String) -> Void = { id in
            if !seen.contains(id) { seen.insert(id); ids.append(id) }
        }
        report.sectors.forEach { $0.evidenceIDs.forEach(append) }
        report.marketOutlook.forEach { $0.evidenceIDs.forEach(append) }
        report.opportunities.forEach { $0.evidenceIDs.forEach(append) }
        return ids
    }

    /// 报告里所有 TrendConfidence，用于范围校验。
    private func collectConfidenceScores(_ report: TrendAnalysisReport) -> [TrendConfidence] {
        var scores: [TrendConfidence] = []
        scores.append(contentsOf: report.horizons.map(\.confidence))
        scores.append(contentsOf: report.sectors.map(\.confidence))
        scores.append(contentsOf: report.marketOutlook.map(\.confidence))
        scores.append(contentsOf: report.opportunities.map(\.confidence))
        scores.append(contentsOf: report.actions.map(\.confidence))
        scores.append(contentsOf: (report.keyAssets + report.assetTrends).flatMap(\.horizons).map(\.confidence))
        return scores
    }
}
