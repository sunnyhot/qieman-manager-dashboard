import XCTest
@testable import QiemanDashboard

final class EnhancementDashboardPresentationTests: XCTestCase {
    func testWorkbenchTabsExcludeImportPreview() {
        XCTAssertEqual(EnhancementCenterTab.workbenchTabs, [.trend])
        XCTAssertFalse(EnhancementCenterTab.review.isVisibleInWorkbench)
        XCTAssertFalse(EnhancementCenterTab.importPreview.isVisibleInWorkbench)
    }

    func testImportPreviewDoesNotDriveWorkbenchPrimaryAction() {
        let summary = makeDashboard(
            importSession: ImportPreviewSession(
                target: .holdings,
                mode: .merge,
                createdAt: "2026-06-17 10:00:00",
                rows: [
                    ImportPreviewRow(
                        id: "blocked",
                        kind: .blocked,
                        title: "没有可导入记录",
                        detail: "请先导入或粘贴有效草稿。",
                        beforeSummary: nil,
                        afterSummary: nil
                    )
                ]
            ),
            watchEvents: [
                event(kind: .failed, title: "巡检失败")
            ],
            lastMonthlyReportExport: MonthlyReportExportMetadata(
                monthText: "2026-06",
                filePath: "/tmp/2026-06-portfolio-report.md",
                exportedAt: "2026-06-17 10:30:00"
            ),
            insight: insufficientInsight()
        )

        XCTAssertEqual(summary.primaryAction.title, "查看趋势")
        XCTAssertEqual(summary.primaryAction.targetTab, .trend)
        XCTAssertEqual(summary.primaryAction.kind, .selectTab)
        XCTAssertFalse(summary.statusCards.contains { $0.tab == .importPreview })
        XCTAssertFalse(summary.actionQueue.contains { $0.targetTab == .importPreview })
        XCTAssertEqual(summary.stateText, "2026-06 · 组合健康")
    }

    func testStatusCardsOnlySurfaceTrendInWorkbench() {
        let session = ImportPreviewSession(
            target: .holdings,
            mode: .merge,
            createdAt: "2026-06-17 10:00:00",
            rows: [
                ImportPreviewRow(id: "added", kind: .added, title: "新增 A", detail: "将新增", beforeSummary: nil, afterSummary: "新"),
                ImportPreviewRow(id: "updated", kind: .updated, title: "更新 B", detail: "将更新", beforeSummary: "旧", afterSummary: "新")
            ]
        )

        let summary = makeDashboard(
            importSession: session,
            watchEvents: [
                event(kind: .noUpdates, title: "巡检完成，无新增")
            ],
            lastMonthlyReportExport: MonthlyReportExportMetadata(
                monthText: "2026-06",
                filePath: "/tmp/2026-06-portfolio-report.md",
                exportedAt: "2026-06-17 10:30:00"
            ),
            insight: readyInsight()
        )

        XCTAssertEqual(summary.statusCards.map(\.tab), [.trend])
        XCTAssertEqual(summary.statusCards.map(\.title), ["趋势分析"])
        XCTAssertEqual(summary.statusCards.first { $0.tab == .trend }?.value, "已生成")
    }

    func testActionQueueIncludesCrossCuttingItems() {
        let session = ImportPreviewSession(
            target: .holdings,
            mode: .merge,
            createdAt: "2026-06-17 10:00:00",
            rows: [
                ImportPreviewRow(id: "added", kind: .added, title: "新增 A", detail: "将新增", beforeSummary: nil, afterSummary: "新")
            ]
        )

        let summary = makeDashboard(
            importSession: session,
            canUndoLatestImport: true,
            watchEvents: [
                event(kind: .failed, title: "巡检失败", detail: "网络错误", errorMessage: "timeout")
            ],
            lastMonthlyReportExport: nil,
            insight: insufficientInsight(),
            reminders: PortfolioReminderSummary(
                headline: "1 项需要处理",
                actionCount: 1,
                items: [
                    PortfolioReminderItem(
                        kind: .pendingTrade,
                        title: "待确认交易",
                        detail: "1 笔买入中或转换记录",
                        metric: "¥700.00",
                        urgency: .high,
                        priority: 10
                    )
                ]
            ),
            planSimulation: PlanSimulationSummary(
                headline: "未来 12 次计划约投入 ¥2,400.00",
                executionCount: 12,
                activePlanCount: 2,
                activeAssetCount: 2,
                totalPerExecutionAmount: 200,
                projectedAmount: 2400,
                totalPerExecutionText: "¥200.00",
                projectedAmountText: "¥2,400.00",
                items: []
            )
        )

        XCTAssertEqual(
            summary.actionQueue.map(\.title),
            [
                "月报未归档",
                "待确认交易",
                "下次计划"
            ]
        )
        XCTAssertFalse(summary.actionQueue.contains { $0.targetTab == .importPreview || $0.targetTab == .watch || $0.targetTab == .insight })
    }

    func testActionQueuePrioritizesTradeSignalAlerts() {
        let summary = makeDashboard(
            lastMonthlyReportExport: MonthlyReportExportMetadata(
                monthText: "2026-06",
                filePath: "/tmp/2026-06-portfolio-report.md",
                exportedAt: "2026-06-17 10:30:00"
            ),
            tradeSignals: TradeSignalSummary(
                headline: "2 条 AI 操作观察",
                generatedAt: "2026-07-03 09:30:00",
                dataAsOf: "2026-07-03 15:00:00",
                triggeredCount: 2,
                staleAnalysis: false,
                items: [
                    tradeSignal(status: .approaching, stale: false)
                ]
            ),
            reminders: PortfolioReminderSummary(
                headline: "1 项需要处理",
                actionCount: 1,
                items: [
                    PortfolioReminderItem(
                        kind: .pendingTrade,
                        title: "待确认交易",
                        detail: "1 笔买入中或转换记录",
                        metric: "¥700.00",
                        urgency: .high,
                        priority: 10
                    )
                ]
            )
        )

        XCTAssertEqual(summary.actionQueue.first?.id, "trade-signals")
        XCTAssertEqual(summary.actionQueue.first?.title, "AI 操作观察")
        XCTAssertEqual(summary.actionQueue.first?.detail, "红利低波：继续回撤")
        XCTAssertEqual(summary.actionQueue.first?.metric, "2 条")
        XCTAssertEqual(summary.actionQueue.first?.targetTab, .trend)
        XCTAssertEqual(summary.actionQueue.first?.kind, .selectTab)
        XCTAssertEqual(summary.actionQueue.first?.severity, .warning)
    }

    func testTrendMissingModelAddsActionQueueItem() {
        let summary = makeDashboard(
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: false,
                generationState: .idle,
                lastGeneratedAt: nil,
                headline: "尚未配置趋势分析模型",
                externalSignalStatus: nil,
                isStale: false
            )
        )

        let item = summary.actionQueue.first { $0.id == "trend-provider" }
        XCTAssertEqual(item?.title, "配置趋势分析模型")
        XCTAssertTrue(item?.detail.contains("OpenAI-compatible") == true)
        XCTAssertEqual(item?.targetTab, .trend)
        XCTAssertEqual(item?.kind, .selectTab)
        XCTAssertEqual(summary.statusCards.first { $0.tab == .trend }?.value, "未配置")
    }

    func testTrendStaleStatusCanTriggerRegeneration() {
        let summary = makeDashboard(
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .succeeded,
                lastGeneratedAt: "2026-06-21 15:00:00",
                headline: "趋势分析已过期",
                externalSignalStatus: .stale,
                isStale: true
            )
        )

        let item = summary.actionQueue.first { $0.id == "trend-refresh" }
        XCTAssertEqual(item?.title, "更新趋势分析")
        XCTAssertEqual(item?.kind, .runTrendAnalysis)
        XCTAssertEqual(summary.statusCards.first { $0.tab == .trend }?.value, "待更新")
    }

    func testTrendUnavailableExternalSignalIsSurfaced() {
        let summary = makeDashboard(
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .succeeded,
                lastGeneratedAt: "2026-06-22 15:00:00",
                headline: "仅本地上下文",
                externalSignalStatus: .unavailable,
                isStale: false
            )
        )

        let item = summary.actionQueue.first { $0.id == "trend-external-unavailable" }
        XCTAssertEqual(item?.title, "外部信号不可用")
        XCTAssertEqual(item?.targetTab, .trend)
        XCTAssertEqual(summary.statusCards.first { $0.tab == .trend }?.value, "已生成")
    }


    func testWatchFilterMatchesExpectedEventKinds() {
        let failed = event(kind: .failed, title: "巡检失败")
        let duplicate = event(kind: .duplicateSuppressed, title: "重复抑制")
        let forumHit = event(kind: .forumHit, title: "新发言")
        let recovered = event(kind: .recovered, title: "巡检恢复")

        XCTAssertTrue(EnhancementWatchFilter.all.matches(failed))
        XCTAssertTrue(EnhancementWatchFilter.failure.matches(failed))
        XCTAssertTrue(EnhancementWatchFilter.duplicate.matches(duplicate))
        XCTAssertTrue(EnhancementWatchFilter.hit.matches(forumHit))
        XCTAssertTrue(EnhancementWatchFilter.recovery.matches(recovered))
        XCTAssertFalse(EnhancementWatchFilter.hit.matches(duplicate))
    }

    func testReportMetadataComputesLineCountAndArchiveState() {
        let summary = makeDashboard(
            report: MonthlyReportSummary(
                title: "且慢主理人看板月报 2026-06",
                monthText: "2026-06",
                generatedAt: "2026-06-17 10:30:00",
                markdown: "# A\n\n## B\n- C"
            ),
            lastMonthlyReportExport: MonthlyReportExportMetadata(
                monthText: "2026-06",
                filePath: "/tmp/2026-06-portfolio-report.md",
                exportedAt: "2026-06-17 10:31:00"
            )
        )

        XCTAssertEqual(summary.reportMetadata.lineCountText, "4 行")
        XCTAssertEqual(summary.reportMetadata.archiveText, "已归档 2026-06-portfolio-report.md")
        XCTAssertTrue(summary.reportMetadata.isArchivedForCurrentMonth)
    }

    private func makeDashboard(
        report: MonthlyReportSummary = MonthlyReportSummary(
            title: "且慢主理人看板月报 2026-06",
            monthText: "2026-06",
            generatedAt: "2026-06-17 10:30:00",
            markdown: "# Report"
        ),
        importSession: ImportPreviewSession? = nil,
        canUndoLatestImport: Bool = false,
        watchEvents: [ManagerWatchTimelineEvent] = [],
        lastMonthlyReportExport: MonthlyReportExportMetadata? = nil,
        cookieAvailable: Bool = true,
        nativeConnectionAvailable: Bool = true,
        insight: PortfolioSnapshotInsightSummary = PortfolioSnapshotInsightSummary(
            headline: "等待组合快照",
            hasEnoughHistory: false,
            cards: []
        ),
        snapshotCount: Int = 0,
        trendStatus: EnhancementTrendStatus = .ready,
        tradeSignals: TradeSignalSummary = TradeSignalSummary(
            headline: "暂无 AI 操作观察",
            generatedAt: nil,
            dataAsOf: nil,
            triggeredCount: 0,
            staleAnalysis: false,
            items: []
        ),
        reminders: PortfolioReminderSummary = PortfolioReminderSummary(headline: "暂无待处理提醒", actionCount: 0, items: []),
        planSimulation: PlanSimulationSummary = PlanSimulationSummary(
            headline: "暂无进行中计划",
            executionCount: 12,
            activePlanCount: 0,
            activeAssetCount: 0,
            totalPerExecutionAmount: 0,
            projectedAmount: 0,
            totalPerExecutionText: "—",
            projectedAmountText: "—",
            items: []
        )
    ) -> EnhancementDashboardSummary {
        EnhancementDashboardSummary.make(
            report: report,
            lastMonthlyReportExport: lastMonthlyReportExport,
            cookieAvailable: cookieAvailable,
            nativeConnectionAvailable: nativeConnectionAvailable,
            watchSummary: ManagerWatchTimelineSummary.make(events: watchEvents),
            importSession: importSession,
            canUndoLatestImport: canUndoLatestImport,
            insightSummary: insight,
            snapshotCount: snapshotCount,
            trendStatus: trendStatus,
            tradeSignals: tradeSignals,
            reminders: reminders,
            planSimulation: planSimulation
        )
    }

    private func event(
        kind: ManagerWatchTimelineEventKind,
        title: String,
        detail: String = "详情",
        errorMessage: String? = nil
    ) -> ManagerWatchTimelineEvent {
        ManagerWatchTimelineEvent(
            kind: kind,
            occurredAt: Date(timeIntervalSince1970: 1_781_600_000),
            prodCode: "LONG_WIN",
            managerName: "ETF拯救世界",
            title: title,
            detail: detail,
            errorMessage: errorMessage
        )
    }

    private func insufficientInsight() -> PortfolioSnapshotInsightSummary {
        PortfolioSnapshotInsightSummary(
            headline: "等待组合快照",
            hasEnoughHistory: false,
            cards: [
                PortfolioSnapshotInsightCard(
                    kind: .coverage,
                    title: "数据覆盖",
                    metric: "1 / 2",
                    detail: "至少需要两次组合快照才能生成变化洞察",
                    tone: .info
                )
            ]
        )
    }

    private func readyInsight() -> PortfolioSnapshotInsightSummary {
        PortfolioSnapshotInsightSummary(
            headline: "组合占用增加 ¥2,500.00",
            hasEnoughHistory: true,
            cards: [
                PortfolioSnapshotInsightCard(
                    kind: .assetChange,
                    title: "资产变化",
                    metric: "+¥2,500.00",
                    detail: "2026-06-16 到 2026-06-17",
                    tone: .gain
                )
            ]
        )
    }

    private func tradeSignal(status: TradeSignalStatus, stale: Bool) -> TradeSignalItem {
        TradeSignalItem(
            id: "buy-000001",
            assetKey: "000001",
            assetName: "红利低波",
            assetCode: "000001",
            action: .watchBuy,
            status: status,
            confidence: TrendConfidence(score: 78, label: "中"),
            title: "关注买入红利低波",
            reason: stale ? "基于上次 AI 分析：回撤未破坏中期逻辑。" : "回撤未破坏中期逻辑。",
            triggerSummary: "继续回撤",
            invalidatingSummary: "趋势破位",
            dataAsOf: "2026-07-03 15:00:00",
            analysisGeneratedAt: stale ? "2026-07-02 09:30:00" : "2026-07-03 09:30:00",
            isBasedOnStaleAnalysis: stale,
            priority: 10
        )
    }
}
