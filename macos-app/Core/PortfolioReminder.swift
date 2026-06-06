import Foundation

enum PortfolioReminderKind: Hashable {
    case pendingTrade
    case investmentPlan
    case concentration
    case dailyMovement
    case quoteCoverage
}

enum PortfolioReminderUrgency: Int, Hashable {
    case high = 0
    case medium = 1
    case low = 2
}

struct PortfolioReminderItem: Identifiable, Hashable {
    let kind: PortfolioReminderKind
    let title: String
    let detail: String
    let metric: String
    let urgency: PortfolioReminderUrgency
    let priority: Int

    var id: PortfolioReminderKind { kind }
}

struct PortfolioReminderSummary: Hashable {
    let headline: String
    let actionCount: Int
    let items: [PortfolioReminderItem]

    static func make(
        rows: [PersonalAssetAggregateRow],
        diagnostics: PortfolioDiagnosticsSummary
    ) -> PortfolioReminderSummary {
        var items: [PortfolioReminderItem] = []

        let pendingAmount = rows.reduce(0) { $0 + $1.pendingCashAmount }
        let pendingCount = rows.reduce(0) { $0 + $1.pendingTradeCount }
        if pendingCount > 0 {
            items.append(
                PortfolioReminderItem(
                    kind: .pendingTrade,
                    title: "待确认交易",
                    detail: "\(pendingCount) 笔买入中或转换记录",
                    metric: currencyText(pendingAmount),
                    urgency: .high,
                    priority: 10
                )
            )
        }

        for diagnostic in diagnostics.items {
            guard diagnostic.level == .risk || diagnostic.level == .watch else { continue }
            guard diagnostic.kind != .pendingExposure && diagnostic.kind != .planCoverage else { continue }
            items.append(
                PortfolioReminderItem(
                    kind: reminderKind(for: diagnostic.kind),
                    title: diagnostic.title,
                    detail: diagnostic.detail,
                    metric: diagnostic.metric,
                    urgency: diagnostic.level == .risk ? .high : .medium,
                    priority: 20 + diagnostic.priority
                )
            )
        }

        if let nextPlan = nextPlanReminder(rows: rows) {
            items.append(nextPlan)
        }

        items.sort { left, right in
            if left.urgency != right.urgency {
                return left.urgency.rawValue < right.urgency.rawValue
            }
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }

        let highCount = items.filter { $0.urgency == .high }.count
        let headline: String
        if highCount > 0 {
            headline = "\(highCount) 项需要处理"
        } else if !items.isEmpty {
            headline = "\(items.count) 项提醒"
        } else {
            headline = "暂无待处理提醒"
        }

        return PortfolioReminderSummary(
            headline: headline,
            actionCount: items.count,
            items: items
        )
    }

    private static func nextPlanReminder(rows: [PersonalAssetAggregateRow]) -> PortfolioReminderItem? {
        let activeRows = rows.filter { $0.activePlanCount > 0 }
        guard !activeRows.isEmpty else { return nil }
        let nextDate = activeRows.compactMap(\.nextExecutionDate).min() ?? "待确认"
        let nextAmount = activeRows.reduce(0) { $0 + $1.estimatedNextPlanAmount }
        return PortfolioReminderItem(
            kind: .investmentPlan,
            title: "下次计划",
            detail: "\(activeRows.count) 个标的有进行中计划 · \(nextDate)",
            metric: currencyText(nextAmount),
            urgency: .medium,
            priority: 80
        )
    }

    private static func reminderKind(for diagnosticKind: PortfolioDiagnosticKind) -> PortfolioReminderKind {
        switch diagnosticKind {
        case .concentration:
            return .concentration
        case .dailyMovement:
            return .dailyMovement
        case .quoteCoverage:
            return .quoteCoverage
        case .pendingExposure:
            return .pendingTrade
        case .planCoverage:
            return .investmentPlan
        }
    }
}

extension AppModel {
    var portfolioReminderSummary: PortfolioReminderSummary {
        PortfolioReminderSummary.make(rows: personalAssetRows, diagnostics: portfolioDiagnosticsSummary)
    }
}
