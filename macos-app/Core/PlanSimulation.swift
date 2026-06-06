import Foundation

struct PlanSimulationItem: Identifiable, Hashable {
    let id: String
    let title: String
    let codeText: String
    let activePlanCount: Int
    let perExecutionAmount: Double
    let projectedAmount: Double
    let perExecutionText: String
    let projectedAmountText: String
    let currentExposureText: String
    let nextExecutionDateText: String
}

struct PlanSimulationSummary: Hashable {
    let headline: String
    let executionCount: Int
    let activePlanCount: Int
    let activeAssetCount: Int
    let totalPerExecutionAmount: Double
    let projectedAmount: Double
    let totalPerExecutionText: String
    let projectedAmountText: String
    let items: [PlanSimulationItem]

    static func make(rows: [PersonalAssetAggregateRow], executionCount: Int = 12) -> PlanSimulationSummary {
        let activeRows = rows.filter { $0.activePlanCount > 0 && $0.estimatedNextPlanAmount > 0 }
        guard !activeRows.isEmpty else {
            return PlanSimulationSummary(
                headline: "暂无进行中计划",
                executionCount: executionCount,
                activePlanCount: 0,
                activeAssetCount: 0,
                totalPerExecutionAmount: 0,
                projectedAmount: 0,
                totalPerExecutionText: "—",
                projectedAmountText: "—",
                items: []
            )
        }

        let totalPerExecution = activeRows.reduce(0) { $0 + $1.estimatedNextPlanAmount }
        let projectedAmount = totalPerExecution * Double(executionCount)
        let activePlanCount = activeRows.reduce(0) { $0 + $1.activePlanCount }
        let items = activeRows
            .map { row in
                let perExecution = row.estimatedNextPlanAmount
                let projected = perExecution * Double(executionCount)
                return PlanSimulationItem(
                    id: row.id,
                    title: row.fundName,
                    codeText: row.fundCode?.isEmpty == false ? row.fundCode! : "—",
                    activePlanCount: row.activePlanCount,
                    perExecutionAmount: perExecution,
                    projectedAmount: projected,
                    perExecutionText: currencyText(perExecution, market: row.detectedMarket),
                    projectedAmountText: currencyText(projected, market: row.detectedMarket),
                    currentExposureText: currencyText(row.effectiveHoldingAmount, market: row.detectedMarket),
                    nextExecutionDateText: row.nextExecutionDate ?? "待确认"
                )
            }
            .sorted { left, right in
                if abs(left.projectedAmount - right.projectedAmount) > 0.001 {
                    return left.projectedAmount > right.projectedAmount
                }
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }

        return PlanSimulationSummary(
            headline: "未来 \(executionCount) 次计划约投入 \(currencyText(projectedAmount))",
            executionCount: executionCount,
            activePlanCount: activePlanCount,
            activeAssetCount: activeRows.count,
            totalPerExecutionAmount: totalPerExecution,
            projectedAmount: projectedAmount,
            totalPerExecutionText: currencyText(totalPerExecution),
            projectedAmountText: currencyText(projectedAmount),
            items: items
        )
    }
}

extension AppModel {
    var planSimulationSummary: PlanSimulationSummary {
        PlanSimulationSummary.make(rows: personalAssetRows)
    }
}
