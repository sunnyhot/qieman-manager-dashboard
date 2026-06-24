import Foundation

struct TrendValidationResult: Hashable {
    let isValid: Bool
    let messages: [String]

    static let valid = TrendValidationResult(isValid: true, messages: [])
}

struct TrendAnalysisValidator {
    private let forbiddenTerms = [
        "必须买入",
        "必须卖出",
        "一定上涨",
        "一定卖出",
        "保证上涨",
        "保证收益"
    ]

    func validate(_ report: TrendAnalysisReport) -> TrendValidationResult {
        var messages: [String] = []

        if report.horizons.isEmpty {
            messages.append("缺少短中长期趋势。")
        }
        for horizon in report.horizons where horizon.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("短中长期趋势缺少 rationale/判断依据：\(horizon.horizon.rawValue)")
        }
        if report.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append("缺少非投资建议声明。")
        }

        for action in report.actions {
            if action.triggerConditions.isEmpty {
                messages.append("行动候选缺少 trigger/触发条件：\(action.title)")
            }
            if action.invalidatingConditions.isEmpty {
                messages.append("行动候选缺少 invalidating/反证条件：\(action.title)")
            }
        }

        let searchableText = ([report.portfolio.headline, report.portfolio.summary, report.disclaimer]
            + report.actions.flatMap { [$0.title, $0.detail] }
            + report.horizons.flatMap { [$0.rationale] + $0.counterSignals })
            .joined(separator: "\n")
        for term in forbiddenTerms where searchableText.contains(term) {
            messages.append("包含强制或 absolute 表述：\(term)")
        }

        return messages.isEmpty ? .valid : TrendValidationResult(isValid: false, messages: messages)
    }
}
