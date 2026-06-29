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

    func validate(_ report: TrendAnalysisReport, expectedFundCodes: [String] = []) -> TrendValidationResult {
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
        if report.externalSignalStatus == .available && report.evidence.isEmpty {
            messages.append("externalSignalStatus 为 available 时必须提供 evidence/证据。")
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
}
