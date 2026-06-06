import Foundation

enum StrategyRadarDimension: CaseIterable, Hashable {
    case activity
    case balance
    case diversity
    case breadth
    case valuation
}

struct StrategyRadarItem: Identifiable, Hashable {
    let dimension: StrategyRadarDimension
    let title: String
    let metric: String
    let detail: String
    let score: Int

    var id: StrategyRadarDimension { dimension }
}

struct StrategyRadarSummary: Hashable {
    let headline: String
    let actionCount: Int
    let buyCount: Int
    let sellCount: Int
    let strategyTypeCount: Int
    let holdingCount: Int
    let items: [StrategyRadarItem]

    static func make(
        actions: [PlatformActionPayload],
        holdings: [HoldingItemPayload]
    ) -> StrategyRadarSummary {
        let buyCount = actions.filter { actionSide($0) == .buy }.count
        let sellCount = actions.filter { actionSide($0) == .sell }.count
        let strategyTypes = Set(
            (actions.compactMap(\.strategyType) + holdings.compactMap(\.strategyType))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let averageValuationChange = average(actions.compactMap(\.valuationChangePct))
        let items = [
            StrategyRadarItem(
                dimension: .activity,
                title: "调仓活跃度",
                metric: "\(actions.count) 次",
                detail: actions.isEmpty ? "等待平台调仓动作" : "最近可见平台调仓动作",
                score: clampedScore(actions.count * 8)
            ),
            StrategyRadarItem(
                dimension: .balance,
                title: "买卖均衡",
                metric: "买 \(buyCount) / 卖 \(sellCount)",
                detail: balanceDetail(buyCount: buyCount, sellCount: sellCount),
                score: balanceScore(buyCount: buyCount, sellCount: sellCount)
            ),
            StrategyRadarItem(
                dimension: .diversity,
                title: "策略多样性",
                metric: "\(strategyTypes.count) 类",
                detail: strategyTypes.isEmpty ? "暂无策略标签" : strategyTypes.sorted().joined(separator: " / "),
                score: clampedScore(strategyTypes.count * 25)
            ),
            StrategyRadarItem(
                dimension: .breadth,
                title: "持仓广度",
                metric: "\(holdings.count) 只",
                detail: holdings.isEmpty ? "等待平台持仓" : "当前平台持仓覆盖",
                score: clampedScore(holdings.count * 10)
            ),
            StrategyRadarItem(
                dimension: .valuation,
                title: "估值反馈",
                metric: averageValuationChange.map { String(format: "%+.2f%%", $0) } ?? "—",
                detail: averageValuationChange == nil ? "暂无调仓后估值变化" : "动作后估值变化均值",
                score: valuationScore(averageValuationChange)
            )
        ]

        return StrategyRadarSummary(
            headline: headline(actionCount: actions.count, buyCount: buyCount, sellCount: sellCount),
            actionCount: actions.count,
            buyCount: buyCount,
            sellCount: sellCount,
            strategyTypeCount: strategyTypes.count,
            holdingCount: holdings.count,
            items: items
        )
    }

    func item(for dimension: StrategyRadarDimension) -> StrategyRadarItem? {
        items.first { $0.dimension == dimension }
    }

    private enum ActionSide {
        case buy
        case sell
    }

    private static func actionSide(_ action: PlatformActionPayload) -> ActionSide? {
        let candidates = [
            action.side,
            action.action,
            action.actionTitle,
            action.title
        ]
        for candidate in candidates {
            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard !value.isEmpty else { continue }
            if value == "buy" || value.contains("买") || value.contains("申购") {
                return .buy
            }
            if value == "sell" || value.contains("卖") || value.contains("赎回") {
                return .sell
            }
        }
        return nil
    }

    private static func headline(actionCount: Int, buyCount: Int, sellCount: Int) -> String {
        guard actionCount > 0 else { return "等待平台数据" }
        if buyCount > sellCount * 3 / 2 {
            return "策略偏进攻"
        }
        if sellCount > buyCount * 3 / 2 {
            return "策略偏防守"
        }
        return "策略攻守均衡"
    }

    private static func balanceDetail(buyCount: Int, sellCount: Int) -> String {
        if buyCount == 0 && sellCount == 0 {
            return "等待买卖方向"
        }
        if buyCount > sellCount {
            return "买入动作更多"
        }
        if sellCount > buyCount {
            return "卖出动作更多"
        }
        return "买卖动作接近"
    }

    private static func balanceScore(buyCount: Int, sellCount: Int) -> Int {
        let total = buyCount + sellCount
        guard total > 0 else { return 0 }
        let imbalance = Double(abs(buyCount - sellCount)) / Double(total)
        return clampedScore(Int((100 - imbalance * 60).rounded()))
    }

    private static func valuationScore(_ value: Double?) -> Int {
        guard let value else { return 0 }
        return clampedScore(Int((50 + value * 8).rounded()))
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func clampedScore(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

extension AppModel {
    var strategyRadarSummary: StrategyRadarSummary {
        StrategyRadarSummary.make(
            actions: platformPayload?.actions ?? [],
            holdings: platformHoldings
        )
    }
}
