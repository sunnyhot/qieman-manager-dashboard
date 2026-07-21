import Foundation

enum DashboardInsightTone: Hashable {
    case brand
    case info
    case warning
    case error
    case positive
    case muted
}

enum DashboardFreshnessKind: Hashable {
    case system
    case portfolio
    case platform
    case forum
    case managerWatch
}

struct DashboardFreshnessContext: Hashable {
    let isRefreshingLatest: Bool
    let isRefreshingPortfolio: Bool
    let globalErrorMessage: String?
    let hasPersonalPortfolio: Bool
    let portfolioRefreshedAt: String?
    let platformLatestTime: String?
    let platformError: String?
    let forumLatestTime: String?
    let managerWatchEnabled: Bool
    let managerLastCheckedAt: String?
    let managerLastSuccessAt: String?
    let managerError: String?
}

struct DashboardFreshnessItem: Identifiable, Hashable {
    let kind: DashboardFreshnessKind
    let title: String
    let status: String
    let detail: String
    let tone: DashboardInsightTone
    let priority: Int

    var id: DashboardFreshnessKind { kind }
}

struct DashboardFreshnessSummary: Hashable {
    let headline: String
    let items: [DashboardFreshnessItem]

    static func make(context: DashboardFreshnessContext) -> DashboardFreshnessSummary {
        var items: [DashboardFreshnessItem] = []

        if let error = trimmed(context.globalErrorMessage) {
            items.append(
                DashboardFreshnessItem(
                    kind: .system,
                    title: "整体刷新",
                    status: "失败",
                    detail: error,
                    tone: .error,
                    priority: 10
                )
            )
        } else if context.isRefreshingLatest {
            items.append(
                DashboardFreshnessItem(
                    kind: .system,
                    title: "整体刷新",
                    status: "进行中",
                    detail: "正在刷新论坛和平台数据",
                    tone: .info,
                    priority: 10
                )
            )
        }

        if let error = trimmed(context.managerError) {
            items.append(
                DashboardFreshnessItem(
                    kind: .managerWatch,
                    title: "主理人巡检",
                    status: "异常",
                    detail: error,
                    tone: .error,
                    priority: 20
                )
            )
        } else if context.managerWatchEnabled {
            items.append(
                DashboardFreshnessItem(
                    kind: .managerWatch,
                    title: "主理人巡检",
                    status: context.managerLastSuccessAt == nil ? "待建立基线" : "正常",
                    detail: context.managerLastSuccessAt ?? context.managerLastCheckedAt ?? "尚未完成巡检",
                    tone: context.managerLastSuccessAt == nil ? .warning : .positive,
                    priority: 60
                )
            )
        }

        items.append(
            DashboardFreshnessItem(
                kind: .portfolio,
                title: "持仓估值",
                status: context.isRefreshingPortfolio ? "刷新中" : portfolioStatus(context),
                detail: portfolioDetail(context),
                tone: context.isRefreshingPortfolio ? .info : (context.portfolioRefreshedAt == nil ? .muted : .positive),
                priority: context.portfolioRefreshedAt == nil ? 80 : 70
            )
        )

        items.append(
            DashboardFreshnessItem(
                kind: .platform,
                title: "平台调仓",
                status: trimmed(context.platformError) == nil ? (context.platformLatestTime == nil ? "待刷新" : "已更新") : "失败",
                detail: trimmed(context.platformError) ?? context.platformLatestTime ?? "暂无平台调仓时间",
                tone: trimmed(context.platformError) == nil ? (context.platformLatestTime == nil ? .muted : .positive) : .error,
                priority: trimmed(context.platformError) == nil ? 75 : 25
            )
        )

        items.append(
            DashboardFreshnessItem(
                kind: .forum,
                title: "论坛发言",
                status: context.forumLatestTime == nil ? "待刷新" : "已更新",
                detail: context.forumLatestTime ?? "暂无论坛发言时间",
                tone: context.forumLatestTime == nil ? .muted : .positive,
                priority: 76
            )
        )

        let sortedItems = items.sorted { left, right in
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }

        let issueCount = sortedItems.filter { $0.tone == .error || $0.tone == .warning }.count
        let headline = issueCount > 0 ? "\(issueCount) 个异常待处理" : "数据状态正常"
        return DashboardFreshnessSummary(headline: headline, items: sortedItems)
    }

    private static func portfolioStatus(_ context: DashboardFreshnessContext) -> String {
        if !context.hasPersonalPortfolio {
            return "未配置"
        }
        return context.portfolioRefreshedAt == nil ? "待估值" : "已更新"
    }

    private static func portfolioDetail(_ context: DashboardFreshnessContext) -> String {
        if let portfolioRefreshedAt = context.portfolioRefreshedAt {
            return portfolioRefreshedAt
        }
        return context.hasPersonalPortfolio ? "等待下一次估值刷新" : "添加持仓后显示估值时间"
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

enum ManagerActivityKind: Hashable {
    case platformAction
    case forumRecord
    case watchStatus
}

struct ManagerActivityContext: Hashable {
    let managerName: String
    let prodCode: String
    let latestPlatformTitle: String?
    let latestPlatformTarget: String?
    let latestPlatformTime: String?
    let latestPlatformChangePct: Double?
    let latestForumTitle: String?
    let latestForumTime: String?
    let latestForumInteraction: String?
    let watchEnabled: Bool
    let watchScopeText: String
    let lastSuccessAt: String?
    let lastError: String?
}

struct ManagerActivityItem: Identifiable, Hashable {
    let kind: ManagerActivityKind
    let title: String
    let detail: String
    let metric: String
    let tone: DashboardInsightTone
    let priority: Int

    var id: ManagerActivityKind { kind }
}

struct ManagerActivitySummary: Hashable {
    let title: String
    let subtitle: String
    let items: [ManagerActivityItem]

    static func make(context: ManagerActivityContext) -> ManagerActivitySummary {
        var items: [ManagerActivityItem] = []

        if let title = trimmed(context.latestPlatformTitle) {
            let target = trimmed(context.latestPlatformTarget)
            let time = trimmed(context.latestPlatformTime)
            items.append(
                ManagerActivityItem(
                    kind: .platformAction,
                    title: "最近调仓",
                    detail: compactParts([title, target, time]).joined(separator: " · "),
                    metric: context.latestPlatformChangePct.map { String(format: "%+.2f%%", $0) } ?? "调仓",
                    tone: .brand,
                    priority: 10
                )
            )
        }

        if let title = trimmed(context.latestForumTitle) {
            items.append(
                ManagerActivityItem(
                    kind: .forumRecord,
                    title: "最近发言",
                    detail: compactParts([title, context.latestForumTime, context.latestForumInteraction]).joined(separator: " · "),
                    metric: "发言",
                    tone: .info,
                    priority: 20
                )
            )
        }

        if let error = trimmed(context.lastError) {
            items.append(
                ManagerActivityItem(
                    kind: .watchStatus,
                    title: "巡检状态",
                    detail: error,
                    metric: "异常",
                    tone: .error,
                    priority: 30
                )
            )
        } else if context.watchEnabled {
            items.append(
                ManagerActivityItem(
                    kind: .watchStatus,
                    title: "巡检状态",
                    detail: context.lastSuccessAt ?? context.watchScopeText,
                    metric: context.lastSuccessAt == nil ? "待基线" : "正常",
                    tone: context.lastSuccessAt == nil ? .warning : .positive,
                    priority: 30
                )
            )
        }

        let fallbackTitle = trimmed(context.managerName) ?? "主理人动态"
        let subtitle = trimmed(context.watchScopeText) ?? trimmed(context.prodCode) ?? "调仓和发言摘要"
        return ManagerActivitySummary(
            title: fallbackTitle,
            subtitle: subtitle,
            items: items.sorted { $0.priority < $1.priority }
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func compactParts(_ values: [String?]) -> [String] {
        values.compactMap(trimmed)
    }
}

extension AppModel {
    var dashboardFreshnessSummary: DashboardFreshnessSummary {
        let latestPlatform = latestPlatformActions.first
        let platformLatestTime = platformPayload?.holdings?.latestTime
            ?? latestPlatform?.txnDate
            ?? latestPlatform?.createdAt
        let forumLatestTime = currentSnapshot?.stats?.latestCreatedAt
            ?? forumRecords.first?.createdAt
            ?? currentSnapshot?.createdAt

        return DashboardFreshnessSummary.make(
            context: DashboardFreshnessContext(
                isRefreshingLatest: isRefreshing,
                isRefreshingPortfolio: isRefreshingPortfolio,
                globalErrorMessage: errorMessage.isEmpty ? nil : errorMessage,
                hasPersonalPortfolio: hasPersonalPortfolio,
                portfolioRefreshedAt: userPortfolioSnapshot?.refreshedAt,
                platformLatestTime: platformLatestTime,
                platformError: platformPayload?.error,
                forumLatestTime: forumLatestTime,
                managerWatchEnabled: managerWatchSettings.isEnabled,
                managerLastCheckedAt: managerWatchSettings.lastCheckedAt,
                managerLastSuccessAt: managerWatchSettings.lastSuccessAt,
                managerError: managerWatchSettings.lastErrorMessage
            )
        )
    }

    var managerActivitySummary: ManagerActivitySummary {
        let latestPlatform = latestPlatformActions.first
        let latestForum = hasForumPosts ? forumRecords.first : nil
        return ManagerActivitySummary.make(
            context: ManagerActivityContext(
                managerName: managerWatchSettings.managerName,
                prodCode: managerWatchSettings.prodCode,
                latestPlatformTitle: latestPlatform?.displayTitle,
                latestPlatformTarget: latestPlatform?.fundName ?? latestPlatform?.fundCode,
                latestPlatformTime: latestPlatform?.txnDate ?? latestPlatform?.createdAt,
                latestPlatformChangePct: latestPlatform?.valuationChangePct,
                latestForumTitle: latestForum?.titleText,
                latestForumTime: latestForum?.createdAt,
                latestForumInteraction: latestForum?.interactionText,
                watchEnabled: managerWatchSettings.isEnabled,
                watchScopeText: managerWatchScopeText,
                lastSuccessAt: managerWatchSettings.lastSuccessAt,
                lastError: managerWatchSettings.lastErrorMessage
            )
        )
    }
}
