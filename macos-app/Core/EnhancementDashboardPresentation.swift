import Foundation

enum EnhancementPresentationSeverity: String, Hashable {
    case brand
    case info
    case positive
    case warning
    case danger
    case neutral
}

enum EnhancementActionKind: String, Hashable {
    case selectTab
    case runTrendAnalysis
    case archiveReport
    case confirmImport
    case undoImport
}

struct EnhancementPrimaryAction: Hashable {
    let title: String
    let systemImage: String
    let targetTab: EnhancementCenterTab
    let kind: EnhancementActionKind
    let severity: EnhancementPresentationSeverity
}

struct EnhancementRuntimeChip: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let severity: EnhancementPresentationSeverity
}

struct EnhancementStatusCard: Identifiable, Hashable {
    var id: EnhancementCenterTab { tab }
    let tab: EnhancementCenterTab
    let title: String
    let value: String
    let detail: String
    let nextAction: String
    let systemImage: String
    let severity: EnhancementPresentationSeverity
}

struct EnhancementActionItem: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let metric: String
    let targetTab: EnhancementCenterTab
    let kind: EnhancementActionKind
    let severity: EnhancementPresentationSeverity
}

struct EnhancementReportMetadata: Hashable {
    let monthText: String
    let generatedAt: String
    let lineCountText: String
    let archiveText: String
    let isArchivedForCurrentMonth: Bool
}

struct EnhancementImportCounts: Hashable {
    let added: Int
    let updated: Int
    let unchanged: Int
    let duplicate: Int
    let removed: Int
    let blocked: Int

    var total: Int {
        added + updated + unchanged + duplicate + removed + blocked
    }

    var hasBlockedRows: Bool {
        blocked > 0
    }

    var summaryText: String {
        var parts: [String] = []
        if added > 0 { parts.append("新增 \(added)") }
        if updated > 0 { parts.append("更新 \(updated)") }
        if duplicate > 0 { parts.append("重复 \(duplicate)") }
        if removed > 0 { parts.append("移除 \(removed)") }
        if blocked > 0 { parts.append("阻塞 \(blocked)") }
        if parts.isEmpty, unchanged > 0 { parts.append("不变 \(unchanged)") }
        return parts.isEmpty ? "暂无预览" : parts.joined(separator: " · ")
    }

    static func make(session: ImportPreviewSession?) -> EnhancementImportCounts {
        guard let session else {
            return EnhancementImportCounts(added: 0, updated: 0, unchanged: 0, duplicate: 0, removed: 0, blocked: 0)
        }
        return EnhancementImportCounts(
            added: session.count(for: .added),
            updated: session.count(for: .updated),
            unchanged: session.count(for: .unchanged),
            duplicate: session.count(for: .duplicate),
            removed: session.count(for: .removed),
            blocked: session.count(for: .blocked)
        )
    }
}

struct EnhancementTrendStatus: Hashable {
    let isProviderConfigured: Bool
    let generationState: TrendGenerationState
    let lastGeneratedAt: String?
    let headline: String
    let externalSignalStatus: TrendExternalSignalStatus?
    let isStale: Bool

    static let ready = EnhancementTrendStatus(
        isProviderConfigured: true,
        generationState: .succeeded,
        lastGeneratedAt: "2026-06-22 10:00:00",
        headline: "趋势分析已生成",
        externalSignalStatus: .available,
        isStale: false
    )

    var valueText: String {
        if !isProviderConfigured {
            return "未配置"
        }
        switch generationState {
        case .generating:
            return "生成中"
        case .failed:
            return "失败"
        case .rejected:
            return "已拦截"
        case .idle, .succeeded:
            if lastGeneratedAt == nil {
                return "未生成"
            }
            return isStale ? "待更新" : "已生成"
        }
    }

    var detailText: String {
        var parts = [headline]
        if let externalSignalStatus {
            parts.append("外部信号 \(externalSignalStatus.rawValue)")
        }
        if let lastGeneratedAt {
            parts.append(lastGeneratedAt)
        }
        return parts.joined(separator: " · ")
    }

    var nextActionText: String {
        if !isProviderConfigured {
            return "配置模型"
        }
        if generationState == .generating {
            return "等待完成"
        }
        if lastGeneratedAt == nil || isStale || generationState == .failed || generationState == .rejected {
            return "重新分析"
        }
        return "查看趋势"
    }

    var severity: EnhancementPresentationSeverity {
        if !isProviderConfigured {
            return .warning
        }
        switch generationState {
        case .generating:
            return .info
        case .failed:
            return .danger
        case .rejected:
            return .warning
        case .idle:
            return lastGeneratedAt == nil ? .info : (isStale ? .warning : .positive)
        case .succeeded:
            if isStale {
                return .warning
            }
            return externalSignalStatus == .unavailable ? .info : .positive
        }
    }
}

enum EnhancementWatchFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "全部"
    case hit = "命中"
    case failure = "失败"
    case duplicate = "重复抑制"
    case recovery = "恢复/完成"

    var id: String { rawValue }

    func matches(_ event: ManagerWatchTimelineEvent) -> Bool {
        switch self {
        case .all:
            return true
        case .hit:
            return event.kind == .forumHit || event.kind == .platformHit
        case .failure:
            return event.kind == .failed
        case .duplicate:
            return event.kind == .duplicateSuppressed
        case .recovery:
            return event.kind == .recovered || event.kind == .noUpdates || event.kind == .pollStarted
        }
    }
}

struct EnhancementDashboardSummary: Hashable {
    let monthText: String
    let stateText: String
    let actionableCount: Int
    let primaryAction: EnhancementPrimaryAction
    let runtimeChips: [EnhancementRuntimeChip]
    let statusCards: [EnhancementStatusCard]
    let actionQueue: [EnhancementActionItem]
    let reportMetadata: EnhancementReportMetadata
    let importCounts: EnhancementImportCounts

    static func make(
        report: MonthlyReportSummary,
        lastMonthlyReportExport: MonthlyReportExportMetadata?,
        cookieAvailable: Bool,
        nativeConnectionAvailable: Bool,
        watchSummary: ManagerWatchTimelineSummary,
        importSession: ImportPreviewSession?,
        canUndoLatestImport: Bool,
        insightSummary: PortfolioSnapshotInsightSummary,
        snapshotCount: Int,
        trendStatus: EnhancementTrendStatus,
        reminders: PortfolioReminderSummary,
        planSimulation: PlanSimulationSummary
    ) -> EnhancementDashboardSummary {
        let reportMetadata = makeReportMetadata(report: report, lastExport: lastMonthlyReportExport)
        let importCounts = EnhancementImportCounts.make(session: importSession)
        let actionQueue = makeActionQueue(
            reportMetadata: reportMetadata,
            watchSummary: watchSummary,
            importSession: importSession,
            importCounts: importCounts,
            canUndoLatestImport: canUndoLatestImport,
            insightSummary: insightSummary,
            trendStatus: trendStatus,
            reminders: reminders,
            planSimulation: planSimulation
        )
        let primaryAction = actionQueue.first.map(primaryAction(from:)) ?? EnhancementPrimaryAction(
            title: "查看趋势",
            systemImage: "sparkles",
            targetTab: .trend,
            kind: .selectTab,
            severity: .brand
        )
        let actionableCount = actionQueue.filter { $0.severity == .warning || $0.severity == .danger }.count
        let state = actionableCount > 0 ? "需要处理" : "组合健康"

        return EnhancementDashboardSummary(
            monthText: report.monthText,
            stateText: "\(report.monthText) · \(state) · \(actionQueue.count) 项待办",
            actionableCount: actionQueue.count,
            primaryAction: primaryAction,
            runtimeChips: makeRuntimeChips(
                cookieAvailable: cookieAvailable,
                nativeConnectionAvailable: nativeConnectionAvailable,
                snapshotCount: snapshotCount,
                watchSummary: watchSummary
            ),
            statusCards: makeStatusCards(
                report: report,
                reportMetadata: reportMetadata,
                watchSummary: watchSummary,
                importSession: importSession,
                importCounts: importCounts,
                canUndoLatestImport: canUndoLatestImport,
                insightSummary: insightSummary,
                snapshotCount: snapshotCount,
                trendStatus: trendStatus
            ),
            actionQueue: actionQueue,
            reportMetadata: reportMetadata,
            importCounts: importCounts
        )
    }

    private static func makeReportMetadata(
        report: MonthlyReportSummary,
        lastExport: MonthlyReportExportMetadata?
    ) -> EnhancementReportMetadata {
        let lineCount = report.markdown.split(separator: "\n", omittingEmptySubsequences: false).count
        let isArchived = lastExport?.monthText == report.monthText
        let archiveText: String
        if let lastExport, isArchived {
            archiveText = "已归档 \(URL(fileURLWithPath: lastExport.filePath).lastPathComponent)"
        } else if let lastExport {
            archiveText = "上次归档 \(lastExport.monthText)"
        } else {
            archiveText = "本月未归档"
        }
        return EnhancementReportMetadata(
            monthText: report.monthText,
            generatedAt: report.generatedAt,
            lineCountText: "\(lineCount) 行",
            archiveText: archiveText,
            isArchivedForCurrentMonth: isArchived
        )
    }

    private static func makeRuntimeChips(
        cookieAvailable: Bool,
        nativeConnectionAvailable: Bool,
        snapshotCount: Int,
        watchSummary: ManagerWatchTimelineSummary
    ) -> [EnhancementRuntimeChip] {
        [
            EnhancementRuntimeChip(
                id: "cookie",
                title: "Cookie",
                value: cookieAvailable ? "可用" : "缺失",
                severity: cookieAvailable ? .positive : .warning
            ),
            EnhancementRuntimeChip(
                id: "native",
                title: "原生直连",
                value: nativeConnectionAvailable ? "可用" : "降级",
                severity: nativeConnectionAvailable ? .info : .warning
            ),
            EnhancementRuntimeChip(
                id: "snapshots",
                title: "快照",
                value: "\(snapshotCount) 次",
                severity: snapshotCount >= 2 ? .positive : .info
            )
        ]
    }

    private static func makeStatusCards(
        report: MonthlyReportSummary,
        reportMetadata: EnhancementReportMetadata,
        watchSummary: ManagerWatchTimelineSummary,
        importSession: ImportPreviewSession?,
        importCounts: EnhancementImportCounts,
        canUndoLatestImport: Bool,
        insightSummary: PortfolioSnapshotInsightSummary,
        snapshotCount: Int,
        trendStatus: EnhancementTrendStatus
    ) -> [EnhancementStatusCard] {
        return [
            EnhancementStatusCard(
                tab: .review,
                title: "本月复盘",
                value: report.monthText,
                detail: reportMetadata.archiveText,
                nextAction: reportMetadata.isArchivedForCurrentMonth ? "查看摘要" : "保存归档",
                systemImage: "doc.text",
                severity: reportMetadata.isArchivedForCurrentMonth ? .positive : .brand
            ),
            EnhancementStatusCard(
                tab: .trend,
                title: "趋势分析",
                value: trendStatus.valueText,
                detail: trendStatus.detailText,
                nextAction: trendStatus.nextActionText,
                systemImage: "sparkles",
                severity: trendStatus.severity
            )
        ]
    }

    private static func makeActionQueue(
        reportMetadata: EnhancementReportMetadata,
        watchSummary: ManagerWatchTimelineSummary,
        importSession: ImportPreviewSession?,
        importCounts: EnhancementImportCounts,
        canUndoLatestImport: Bool,
        insightSummary: PortfolioSnapshotInsightSummary,
        trendStatus: EnhancementTrendStatus,
        reminders: PortfolioReminderSummary,
        planSimulation: PlanSimulationSummary
    ) -> [EnhancementActionItem] {
        var items: [EnhancementActionItem] = []

        if !reportMetadata.isArchivedForCurrentMonth {
            items.append(EnhancementActionItem(
                id: "report-archive",
                title: "月报未归档",
                detail: reportMetadata.monthText,
                metric: reportMetadata.lineCountText,
                targetTab: .review,
                kind: .archiveReport,
                severity: .info
            ))
        }

        if !trendStatus.isProviderConfigured {
            items.append(EnhancementActionItem(
                id: "trend-provider",
                title: "配置趋势分析模型",
                detail: "填写 OpenAI-compatible 模型地址、模型名称和 API Key 后才能生成趋势分析",
                metric: "模型",
                targetTab: .trend,
                kind: .selectTab,
                severity: .warning
            ))
        } else if trendStatus.lastGeneratedAt == nil {
            items.append(EnhancementActionItem(
                id: "trend-generate",
                title: "生成趋势分析",
                detail: "结合持仓、平台动态和外部信号生成条件式趋势",
                metric: "未生成",
                targetTab: .trend,
                kind: .runTrendAnalysis,
                severity: .info
            ))
        } else if trendStatus.isStale || trendStatus.generationState == .failed || trendStatus.generationState == .rejected {
            items.append(EnhancementActionItem(
                id: "trend-refresh",
                title: "更新趋势分析",
                detail: trendStatus.headline,
                metric: trendStatus.valueText,
                targetTab: .trend,
                kind: .runTrendAnalysis,
                severity: trendStatus.generationState == .failed ? .warning : .info
            ))
        }

        if trendStatus.externalSignalStatus == .unavailable, trendStatus.lastGeneratedAt != nil {
            items.append(EnhancementActionItem(
                id: "trend-external-unavailable",
                title: "外部信号不可用",
                detail: "当前报告只基于本地上下文，需留意数据边界",
                metric: "本地",
                targetTab: .trend,
                kind: .selectTab,
                severity: .info
            ))
        }

        items.append(contentsOf: reminders.items.prefix(3).map { reminder in
            EnhancementActionItem(
                id: "reminder-\(reminder.kind)",
                title: reminder.title,
                detail: reminder.detail,
                metric: reminder.metric,
                targetTab: .review,
                kind: .selectTab,
                severity: reminder.urgency == .high ? .warning : .info
            )
        })

        if planSimulation.activePlanCount > 0 {
            items.append(EnhancementActionItem(
                id: "plan-next",
                title: "下次计划",
                detail: "\(planSimulation.activeAssetCount) 个标的有进行中计划",
                metric: planSimulation.totalPerExecutionText,
                targetTab: .review,
                kind: .selectTab,
                severity: .info
            ))
        }

        return items
    }

    private static func primaryAction(from item: EnhancementActionItem) -> EnhancementPrimaryAction {
        let systemImage: String
        let title: String
        switch item.kind {
        case .confirmImport:
            title = item.title
            systemImage = "checkmark.circle"
        case .undoImport:
            title = item.title
            systemImage = "arrow.uturn.backward"
        case .runTrendAnalysis:
            title = item.title
            systemImage = "wand.and.stars"
        case .archiveReport:
            title = "保存月报"
            systemImage = "archivebox"
        case .selectTab:
            title = item.title
            systemImage = "arrow.right.circle"
        }
        return EnhancementPrimaryAction(
            title: title,
            systemImage: systemImage,
            targetTab: item.targetTab,
            kind: item.kind,
            severity: item.severity
        )
    }
}
