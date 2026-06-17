# Enhancement Center Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `增强` section as a professional monthly investment workbench with clear status, next actions, and refined workflows.

**Architecture:** Add a pure Swift presentation model that converts existing AppModel summaries into status cards, report metadata, watch filters, and an action queue. Refactor `EnhancementCenterView` to consume that model and keep SwiftUI focused on layout and interaction, while existing Core export/import/watch/insight logic remains unchanged.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, XCTest, existing `AppPalette`, existing AppModel enhancement state, no new UI or chart dependencies.

---

## Files And Responsibilities

- Create `macos-app/Core/EnhancementDashboardPresentation.swift`: pure presentation types for header state, runtime chips, status cards, primary action, action queue, report metadata, import counts, and watch filtering.
- Create `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`: red-green coverage for action priority, card mapping, action queue, watch filtering, and report metadata.
- Modify `macos-app/Views/EnhancementCenterView.swift`: replace the rough utility layout with a monthly workbench shell, clickable status cards, action queue rail, refined workflow panels, and adaptive split layout.
- Do not modify persistence formats, import parsing, manager watch behavior, release metadata, or other app sections.

## Implementation Notes

- Keep Chinese market color convention: gains red, losses green via `AppPalette`.
- Use native SwiftUI controls and SF Symbols only.
- Keep `EnhancementCenterView` below roughly 650 lines if practical. If it grows beyond that, split view-only helpers under `macos-app/Views/Enhancement/`.
- Presentation model functions should not touch `AppModel`, files, network, pasteboard, or AppKit.

---

### Task 1: Presentation Model Core

**Files:**
- Create: `macos-app/Core/EnhancementDashboardPresentation.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class EnhancementDashboardPresentationTests: XCTestCase {
    func testPrimaryActionPrioritizesBlockedImportPreview() {
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
            lastMonthlyReportExport: nil,
            insight: insufficientInsight()
        )

        XCTAssertEqual(summary.primaryAction.title, "处理导入阻塞")
        XCTAssertEqual(summary.primaryAction.targetTab, .importPreview)
        XCTAssertEqual(summary.primaryAction.kind, .selectTab)
        XCTAssertEqual(summary.primaryAction.severity, .danger)
        XCTAssertEqual(summary.stateText, "2026-06 · 需要处理 · 3 项待办")
    }

    func testStatusCardsMapTabsToValuesAndNextActions() {
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

        XCTAssertEqual(summary.statusCards.map(\.tab), [.review, .watch, .importPreview, .insight])
        XCTAssertEqual(summary.statusCards.first { $0.tab == .review }?.value, "2026-06")
        XCTAssertEqual(summary.statusCards.first { $0.tab == .review }?.nextAction, "查看摘要")
        XCTAssertEqual(summary.statusCards.first { $0.tab == .watch }?.value, "巡检完成，无新增")
        XCTAssertEqual(summary.statusCards.first { $0.tab == .importPreview }?.value, "2 条待确认")
        XCTAssertEqual(summary.statusCards.first { $0.tab == .importPreview }?.detail, "新增 1 · 更新 1")
        XCTAssertEqual(summary.statusCards.first { $0.tab == .insight }?.value, "已生成")
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
                "确认导入预览",
                "可撤销上次导入",
                "巡检失败",
                "月报未归档",
                "洞察需要快照",
                "待确认交易",
                "下次计划"
            ]
        )
        XCTAssertEqual(summary.actionQueue.first?.targetTab, .importPreview)
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
        lastMonthlyReportExport: MonthlyReportExportMetadata? = nil,
        cookieAvailable: Bool = true,
        nativeConnectionAvailable: Bool = true,
        importSession: ImportPreviewSession? = nil,
        canUndoLatestImport: Bool = false,
        watchEvents: [ManagerWatchTimelineEvent] = [],
        insight: PortfolioSnapshotInsightSummary = PortfolioSnapshotInsightSummary(
            headline: "等待组合快照",
            hasEnoughHistory: false,
            cards: []
        ),
        snapshotCount: Int = 0,
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
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests
```

Expected: FAIL with errors such as `cannot find type 'EnhancementDashboardSummary' in scope` and `cannot find 'EnhancementWatchFilter' in scope`.

- [ ] **Step 3: Add the presentation model**

Create `macos-app/Core/EnhancementDashboardPresentation.swift`:

```swift
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
    case runWatch
    case archiveReport
    case confirmImport
    case undoImport
    case recordSnapshot
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
            reminders: reminders,
            planSimulation: planSimulation
        )
        let primaryAction = actionQueue.first.map(primaryAction(from:)) ?? EnhancementPrimaryAction(
            title: "查看洞察",
            systemImage: "chart.xyaxis.line",
            targetTab: .insight,
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
                snapshotCount: snapshotCount
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
            ),
            EnhancementRuntimeChip(
                id: "watch",
                title: "巡检",
                value: watchSummary.events.first?.occurredAt.formatted(date: .numeric, time: .shortened) ?? "暂无",
                severity: watchSummary.failureCount > 0 ? .warning : .info
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
        snapshotCount: Int
    ) -> [EnhancementStatusCard] {
        let importValue: String
        let importSeverity: EnhancementPresentationSeverity
        let importNextAction: String
        if importCounts.hasBlockedRows {
            importValue = "\(importCounts.blocked) 条阻塞"
            importSeverity = .danger
            importNextAction = "处理阻塞"
        } else if let importSession {
            importValue = "\(importSession.rows.count) 条待确认"
            importSeverity = importSession.canConfirm ? .warning : .neutral
            importNextAction = importSession.canConfirm ? "确认写入" : "查看预览"
        } else if canUndoLatestImport {
            importValue = "可撤销"
            importSeverity = .warning
            importNextAction = "检查撤销"
        } else {
            importValue = "安全"
            importSeverity = .positive
            importNextAction = "生成预览"
        }

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
                tab: .watch,
                title: "巡检",
                value: watchSummary.latestStatusText,
                detail: "\(watchSummary.events.count) 条记录 · 失败 \(watchSummary.failureCount)",
                nextAction: watchSummary.failureCount > 0 ? "查看失败" : "查看时间线",
                systemImage: "bell.badge",
                severity: watchSummary.failureCount > 0 ? .warning : .positive
            ),
            EnhancementStatusCard(
                tab: .importPreview,
                title: "导入安全",
                value: importValue,
                detail: importCounts.summaryText,
                nextAction: importNextAction,
                systemImage: "arrow.triangle.2.circlepath",
                severity: importSeverity
            ),
            EnhancementStatusCard(
                tab: .insight,
                title: "组合洞察",
                value: insightSummary.hasEnoughHistory ? "已生成" : "待快照",
                detail: "\(snapshotCount) 次快照 · \(insightSummary.headline)",
                nextAction: insightSummary.hasEnoughHistory ? "查看洞察" : "生成快照",
                systemImage: "chart.xyaxis.line",
                severity: insightSummary.hasEnoughHistory ? .positive : .info
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
        reminders: PortfolioReminderSummary,
        planSimulation: PlanSimulationSummary
    ) -> [EnhancementActionItem] {
        var items: [EnhancementActionItem] = []

        if importCounts.hasBlockedRows {
            items.append(EnhancementActionItem(
                id: "import-blocked",
                title: "处理导入阻塞",
                detail: "\(importCounts.blocked) 条记录阻止写入",
                metric: "\(importCounts.blocked)",
                targetTab: .importPreview,
                kind: .selectTab,
                severity: .danger
            ))
        } else if let importSession, importSession.canConfirm {
            items.append(EnhancementActionItem(
                id: "import-confirm",
                title: "确认导入预览",
                detail: "\(importSession.rows.count) 条变更等待写入",
                metric: "\(importSession.rows.count)",
                targetTab: .importPreview,
                kind: .confirmImport,
                severity: .warning
            ))
        }

        if canUndoLatestImport {
            items.append(EnhancementActionItem(
                id: "import-undo",
                title: "可撤销上次导入",
                detail: "本地数据仍匹配撤销快照",
                metric: "可撤销",
                targetTab: .importPreview,
                kind: .undoImport,
                severity: .warning
            ))
        }

        if watchSummary.events.first?.kind == .failed {
            items.append(EnhancementActionItem(
                id: "watch-failed",
                title: "巡检失败",
                detail: watchSummary.events.first?.errorMessage ?? watchSummary.events.first?.detail ?? "查看失败原因",
                metric: "\(watchSummary.failureCount)",
                targetTab: .watch,
                kind: .selectTab,
                severity: .warning
            ))
        } else if watchSummary.events.isEmpty {
            items.append(EnhancementActionItem(
                id: "watch-empty",
                title: "尚无巡检记录",
                detail: "运行一次手动巡检建立状态线",
                metric: "0",
                targetTab: .watch,
                kind: .runWatch,
                severity: .info
            ))
        }

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

        if !insightSummary.hasEnoughHistory {
            items.append(EnhancementActionItem(
                id: "insight-snapshot",
                title: "洞察需要快照",
                detail: insightSummary.headline,
                metric: "缺数据",
                targetTab: .insight,
                kind: .recordSnapshot,
                severity: .info
            ))
        }

        items.append(contentsOf: reminders.items.prefix(3).map { reminder in
            EnhancementActionItem(
                id: "reminder-\(reminder.kind)",
                title: reminder.title,
                detail: reminder.detail,
                metric: reminder.metric,
                targetTab: .insight,
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
                targetTab: .insight,
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
        case .runWatch:
            title = "立即巡检"
            systemImage = "play.circle"
        case .archiveReport:
            title = "保存月报"
            systemImage = "archivebox"
        case .recordSnapshot:
            title = "生成快照"
            systemImage = "camera.metering.center.weighted"
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
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add macos-app/Core/EnhancementDashboardPresentation.swift macos-app/Tests/QiemanDashboardTests/EnhancementDashboardPresentationTests.swift
git commit -m "feat: add enhancement dashboard presentation"
```

---

### Task 2: Workbench Shell, Header, Status Cards, And Action Queue

**Files:**
- Modify: `macos-app/Views/EnhancementCenterView.swift`

- [ ] **Step 1: Add view state and computed presentation summary**

Open `macos-app/Views/EnhancementCenterView.swift`. In `EnhancementCenterView`, add these `@State` properties near the existing state properties:

```swift
@State private var selectedWatchFilter: EnhancementWatchFilter = .all
@State private var isMonthlyReportPreviewExpanded = false
```

Add this computed property near the existing private computed properties:

```swift
private var dashboardSummary: EnhancementDashboardSummary {
    EnhancementDashboardSummary.make(
        report: model.monthlyReportSummary,
        lastMonthlyReportExport: model.lastMonthlyReportExport,
        cookieAvailable: model.cookieAvailable,
        nativeConnectionAvailable: true,
        watchSummary: model.managerWatchTimelineSummary,
        importSession: model.activeImportPreviewSession,
        canUndoLatestImport: model.canUndoLatestImport,
        insightSummary: model.portfolioSnapshotInsightSummary,
        snapshotCount: model.portfolioInsightSnapshots.count,
        reminders: model.portfolioReminderSummary,
        planSimulation: model.planSimulationSummary
    )
}
```

- [ ] **Step 2: Replace the body content stack**

In the `ScrollView` body, replace the inner `VStack` content with:

```swift
VStack(alignment: .leading, spacing: AppPalette.spaceL) {
    dashboardHeader
    statusCardGrid
    workbenchContent
}
.padding(AppPalette.spaceXL)
```

Keep the existing `.fileImporter` and `.alert` modifiers unchanged.

- [ ] **Step 3: Add dashboard header**

Add this view helper inside `EnhancementCenterView`:

```swift
private var dashboardHeader: some View {
    VStack(alignment: .leading, spacing: AppPalette.spaceM) {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AppPalette.spaceL) {
                headerTitleBlock
                Spacer(minLength: AppPalette.spaceM)
                primaryActionButton(dashboardSummary.primaryAction)
            }

            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                headerTitleBlock
                primaryActionButton(dashboardSummary.primaryAction)
            }
        }

        FlowLayout(spacing: AppPalette.spaceS) {
            ForEach(dashboardSummary.runtimeChips) { chip in
                runtimeChip(chip)
            }
        }
    }
    .padding(AppPalette.spaceXL)
    .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
    .cardStroke()
}

private var headerTitleBlock: some View {
    VStack(alignment: .leading, spacing: AppPalette.spaceS) {
        Text("月度增强工作台")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(AppPalette.ink)
        Text(dashboardSummary.stateText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppPalette.muted)
    }
}

private func runtimeChip(_ chip: EnhancementRuntimeChip) -> some View {
    HStack(spacing: AppPalette.spaceXS) {
        Text(chip.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppPalette.muted)
        Text(chip.value)
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint(for: chip.severity))
    }
    .padding(.horizontal, AppPalette.spaceS)
    .padding(.vertical, AppPalette.spaceXS)
    .background(tint(for: chip.severity).opacity(AppPalette.accentFill), in: Capsule())
    .overlay(Capsule().stroke(tint(for: chip.severity).opacity(AppPalette.accentBorder), lineWidth: 1))
}
```

- [ ] **Step 4: Add status cards**

Replace the old `summaryGrid` usage with a new helper:

```swift
private var statusCardGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: AppPalette.spaceM)], spacing: AppPalette.spaceM) {
        ForEach(dashboardSummary.statusCards) { card in
            Button {
                model.selectedEnhancementTab = card.tab
            } label: {
                enhancementStatusCard(card)
            }
            .buttonStyle(PressResponsiveButtonStyle())
            .help(card.nextAction)
        }
    }
}

private func enhancementStatusCard(_ card: EnhancementStatusCard) -> some View {
    VStack(alignment: .leading, spacing: AppPalette.spaceM) {
        HStack(alignment: .top, spacing: AppPalette.spaceS) {
            Image(systemName: card.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint(for: card.severity))
                .accentIconStyle(tint: tint(for: card.severity), size: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                Text(card.value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }

        Text(card.detail)
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
            .lineLimit(2)
            .frame(minHeight: 26, alignment: .topLeading)

        HStack(spacing: AppPalette.spaceXS) {
            Text(card.nextAction)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint(for: card.severity))
            Spacer(minLength: 0)
            Image(systemName: model.selectedEnhancementTab == card.tab ? "checkmark.circle.fill" : "arrow.right.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint(for: card.severity))
        }
    }
    .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
    .padding(AppPalette.spaceM)
    .interactiveSurface(
        isSelected: model.selectedEnhancementTab == card.tab,
        tint: tint(for: card.severity),
        radius: AppPalette.cardRadius,
        fill: AppPalette.card,
        hoverFill: AppPalette.cardHover
    )
}
```

- [ ] **Step 5: Add main workbench split and action queue**

Add these helpers:

```swift
private var workbenchContent: some View {
    ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: AppPalette.spaceL) {
            VStack(alignment: .leading, spacing: AppPalette.spaceM) {
                tabPicker
                selectedWorkflowPanel
            }
            .frame(minWidth: 620, maxWidth: .infinity, alignment: .topLeading)

            actionQueueRail
                .frame(width: 320)
        }

        VStack(alignment: .leading, spacing: AppPalette.spaceL) {
            tabPicker
            selectedWorkflowPanel
            actionQueueRail
        }
    }
}

private var tabPicker: some View {
    Picker("增强中心", selection: $model.selectedEnhancementTab) {
        ForEach(EnhancementCenterTab.allCases) { tab in
            Text(tab.rawValue).tag(tab)
        }
    }
    .pickerStyle(.segmented)
}

@ViewBuilder
private var selectedWorkflowPanel: some View {
    switch model.selectedEnhancementTab {
    case .review:
        reviewPanel
    case .watch:
        watchPanel
    case .importPreview:
        importPanel
    case .insight:
        insightPanel
    }
}

private var actionQueueRail: some View {
    SectionCard(title: "行动队列", subtitle: "\(dashboardSummary.actionQueue.count) 项待办", icon: "checklist") {
        if dashboardSummary.actionQueue.isEmpty {
            emptyState("暂无待办", detail: "本月复盘、导入、巡检和洞察都没有需要立即处理的事项。")
        } else {
            LazyVStack(alignment: .leading, spacing: AppPalette.spaceS) {
                ForEach(dashboardSummary.actionQueue) { item in
                    Button {
                        perform(item)
                    } label: {
                        actionQueueItem(item)
                    }
                    .buttonStyle(.plain)
                    .help(item.detail)
                }
            }
        }
    }
}

private func actionQueueItem(_ item: EnhancementActionItem) -> some View {
    HStack(alignment: .top, spacing: AppPalette.spaceS) {
        Circle()
            .fill(tint(for: item.severity))
            .frame(width: 8, height: 8)
            .padding(.top, 5)

        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(item.detail)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
        }

        Spacer(minLength: 0)

        Text(item.metric)
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint(for: item.severity))
    }
    .padding(AppPalette.spaceS)
    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    .overlay(RoundedRectangle(cornerRadius: AppPalette.controlRadius).stroke(tint(for: item.severity).opacity(0.18), lineWidth: 1))
}
```

- [ ] **Step 6: Add actions and severity tint**

Add these methods:

```swift
private func perform(_ item: EnhancementActionItem) {
    switch item.kind {
    case .confirmImport:
        model.selectedEnhancementTab = .importPreview
        model.confirmActiveImportPreview()
    case .undoImport:
        model.selectedEnhancementTab = .importPreview
        model.undoLatestImport()
    case .runWatch:
        model.selectedEnhancementTab = .watch
        model.runManagerWatchNow()
    case .archiveReport:
        model.selectedEnhancementTab = .review
        model.archiveMonthlyReport()
    case .recordSnapshot:
        model.selectedEnhancementTab = .insight
        model.recordPortfolioInsightSnapshotIfPossible()
    case .selectTab:
        model.selectedEnhancementTab = item.targetTab
    }
}

private func primaryActionButton(_ action: EnhancementPrimaryAction) -> some View {
    Button {
        perform(EnhancementActionItem(
            id: "primary",
            title: action.title,
            detail: action.title,
            metric: "",
            targetTab: action.targetTab,
            kind: action.kind,
            severity: action.severity
        ))
    } label: {
        Label(action.title, systemImage: action.systemImage)
            .font(.system(size: 12, weight: .bold))
    }
    .buttonStyle(.borderedProminent)
    .tint(tint(for: action.severity))
}

private func tint(for severity: EnhancementPresentationSeverity) -> Color {
    switch severity {
    case .brand:
        return AppPalette.brand
    case .info:
        return AppPalette.info
    case .positive:
        return AppPalette.positive
    case .warning:
        return AppPalette.warning
    case .danger:
        return AppPalette.danger
    case .neutral:
        return AppPalette.muted
    }
}
```

- [ ] **Step 7: Build after shell refactor**

Run:

```bash
swift build --package-path macos-app --build-tests
```

Expected: PASS. If the build fails due to the manual watch method name, apply the method-name fix from Step 6 and rerun.

- [ ] **Step 8: Commit**

```bash
git add macos-app/Views/EnhancementCenterView.swift
git commit -m "feat: add enhancement workbench shell"
```

---

### Task 3: Review Panel Upgrade

**Files:**
- Modify: `macos-app/Views/EnhancementCenterView.swift`

- [ ] **Step 1: Replace `reviewPanel`**

Replace the existing `reviewPanel` with:

```swift
private var reviewPanel: some View {
    SectionCard(title: "复盘", subtitle: model.monthlyReportSummary.title, icon: "doc.text") {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            reportStatusStrip
            reportSummaryGrid
            reportActionRow
            monthlyReportPreview
        }
    }
}
```

- [ ] **Step 2: Add report status strip and action row**

Add:

```swift
private var reportStatusStrip: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
        compactFact("报告月份", dashboardSummary.reportMetadata.monthText, tint: AppPalette.brand)
        compactFact("生成时间", dashboardSummary.reportMetadata.generatedAt, tint: AppPalette.info)
        compactFact("Markdown", dashboardSummary.reportMetadata.lineCountText, tint: AppPalette.positive)
        compactFact("归档", dashboardSummary.reportMetadata.archiveText, tint: dashboardSummary.reportMetadata.isArchivedForCurrentMonth ? AppPalette.positive : AppPalette.warning)
    }
}

private var reportActionRow: some View {
    ViewThatFits(in: .horizontal) {
        HStack(spacing: AppPalette.spaceS) {
            reportActions
            Spacer(minLength: 0)
        }
        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            reportActions
        }
    }
}

private func compactFact(_ title: String, _ value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppPalette.muted)
        Text(value)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(AppPalette.spaceS)
    .background(tint.opacity(AppPalette.accentFill), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    .overlay(RoundedRectangle(cornerRadius: AppPalette.controlRadius).stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1))
}
```

- [ ] **Step 3: Add report summary grid**

Add:

```swift
private var reportSummaryGrid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
        compactFact("组合诊断", model.portfolioDiagnosticsSummary.headline, tint: AppPalette.info)
        compactFact("提醒通知", model.portfolioReminderSummary.headline, tint: model.portfolioReminderSummary.actionCount > 0 ? AppPalette.warning : AppPalette.positive)
        compactFact("收益归因", model.profitAttributionSummary.headline, tint: AppPalette.marketTint(for: model.profitAttributionSummary.totalProfitValue))
        compactFact("计划模拟", model.planSimulationSummary.headline, tint: model.planSimulationSummary.activePlanCount > 0 ? AppPalette.info : AppPalette.muted)
    }
}
```

- [ ] **Step 4: Add collapsible Markdown preview**

Replace the raw Markdown `Text` block with:

```swift
private var monthlyReportPreview: some View {
    VStack(alignment: .leading, spacing: AppPalette.spaceS) {
        HStack {
            Text("Markdown 预览")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isMonthlyReportPreviewExpanded.toggle()
                }
            } label: {
                Label(isMonthlyReportPreviewExpanded ? "收起" : "展开全文", systemImage: isMonthlyReportPreviewExpanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.bordered)
        }

        Text(model.monthlyReportSummary.markdown)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(AppPalette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: isMonthlyReportPreviewExpanded ? .infinity : 260, alignment: .top)
            .clipped()
            .padding(AppPalette.spaceM)
            .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: AppPalette.cardRadius).stroke(AppPalette.line.opacity(AppPalette.borderFaint), lineWidth: 1))
    }
}
```

- [ ] **Step 5: Build focused target**

Run:

```bash
swift build --package-path macos-app --build-tests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Views/EnhancementCenterView.swift
git commit -m "feat: refine enhancement review panel"
```

---

### Task 4: Watch Panel Filters And Operations Log

**Files:**
- Modify: `macos-app/Views/EnhancementCenterView.swift`

- [ ] **Step 1: Replace `watchPanel`**

Replace the existing `watchPanel` with:

```swift
private var watchPanel: some View {
    SectionCard(title: "巡检", subtitle: model.managerWatchTimelineSummary.latestStatusText, icon: "bell.badge") {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            watchStatusStrip
            watchFilterRow
            watchTimelineList
        }
    }
}
```

- [ ] **Step 2: Add watch status strip and filters**

Add:

```swift
private var watchStatusStrip: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
        compactFact("最新状态", model.managerWatchTimelineSummary.latestStatusText, tint: model.managerWatchTimelineSummary.failureCount > 0 ? AppPalette.warning : AppPalette.positive)
        compactFact("失败次数", "\(model.managerWatchTimelineSummary.failureCount)", tint: model.managerWatchTimelineSummary.failureCount > 0 ? AppPalette.warning : AppPalette.positive)
        compactFact("时间线", "\(model.managerWatchTimelineSummary.events.count) 条", tint: AppPalette.info)
    }
}

private var watchFilterRow: some View {
    FlowLayout(spacing: AppPalette.spaceS) {
        ForEach(EnhancementWatchFilter.allCases) { filter in
            Button {
                selectedWatchFilter = filter
            } label: {
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, AppPalette.spaceS)
                    .padding(.vertical, AppPalette.spaceXS)
            }
            .buttonStyle(.plain)
            .background(
                selectedWatchFilter == filter ? AppPalette.brand.opacity(0.14) : AppPalette.cardStrong,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(selectedWatchFilter == filter ? AppPalette.brand.opacity(0.55) : AppPalette.line.opacity(0.28), lineWidth: 1)
            )
            .foregroundStyle(selectedWatchFilter == filter ? AppPalette.brand : AppPalette.muted)
        }
    }
}
```

- [ ] **Step 3: Add filtered timeline list**

Add:

```swift
private var filteredWatchEvents: [ManagerWatchTimelineEvent] {
    model.managerWatchTimelineSummary.events.filter { selectedWatchFilter.matches($0) }
}

private var watchTimelineList: some View {
    Group {
        if model.managerWatchTimelineEvents.isEmpty {
            emptyState("暂无巡检时间线", detail: "开启主理人提醒或点击立即巡检后，这里会记录命中、失败和重复通知抑制。")
        } else if filteredWatchEvents.isEmpty {
            emptyState("当前筛选无记录", detail: "切换到全部可以查看完整巡检时间线。")
        } else {
            LazyVStack(alignment: .leading, spacing: AppPalette.spaceS) {
                ForEach(filteredWatchEvents) { event in
                    timelineRow(event)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Improve `timelineRow` visual hierarchy**

In `timelineRow(_:)`, replace the leading `Circle()` with:

```swift
Image(systemName: icon(for: event.kind))
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(tint(for: event.tone))
    .accentIconStyle(tint: tint(for: event.tone), size: 28)
```

Add:

```swift
private func icon(for kind: ManagerWatchTimelineEventKind) -> String {
    switch kind {
    case .pollStarted:
        return "play.circle"
    case .forumHit:
        return "text.bubble"
    case .platformHit:
        return "chart.bar.doc.horizontal"
    case .duplicateSuppressed:
        return "bell.slash"
    case .noUpdates:
        return "checkmark.circle"
    case .failed:
        return "exclamationmark.triangle"
    case .recovered:
        return "arrow.clockwise.circle"
    }
}
```

- [ ] **Step 5: Run focused tests and build**

Run:

```bash
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests/testWatchFilterMatchesExpectedEventKinds
swift build --package-path macos-app --build-tests
```

Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Views/EnhancementCenterView.swift
git commit -m "feat: refine enhancement watch timeline"
```

---

### Task 5: Import Panel Review Flow

**Files:**
- Modify: `macos-app/Views/EnhancementCenterView.swift`

- [ ] **Step 1: Replace `importPanel` body ordering**

Keep the existing file importer behavior. Replace the content inside `SectionCard(title: "导入预演"...` with:

```swift
VStack(alignment: .leading, spacing: AppPalette.spaceM) {
    importControlBar
    importDraftEditor
    importPreviewSummary
    importActionFooter
    if let session = model.activeImportPreviewSession {
        importPreviewRows(session)
    } else {
        emptyState("暂无导入预览", detail: "粘贴草稿或导入文件后点击生成预览。")
    }
}
```

- [ ] **Step 2: Add import control bar and draft editor**

Add:

```swift
private var importControlBar: some View {
    ViewThatFits(in: .horizontal) {
        HStack(spacing: AppPalette.spaceS) {
            importControls
            Button {
                model.prepareImportPreview(target: importTarget, mode: importMode)
            } label: {
                Label("生成预览", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brand)
            Spacer(minLength: 0)
        }

        VStack(alignment: .leading, spacing: AppPalette.spaceS) {
            importControls
            Button {
                model.prepareImportPreview(target: importTarget, mode: importMode)
            } label: {
                Label("生成预览", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppPalette.brand)
        }
    }
}

private var importDraftEditor: some View {
    VStack(alignment: .leading, spacing: AppPalette.spaceS) {
        Text("源草稿")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppPalette.ink)
        TextEditor(text: draftBinding)
            .font(.system(size: 11, design: .monospaced))
            .frame(minHeight: 120)
            .padding(AppPalette.spaceS)
            .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: AppPalette.cardRadius).stroke(AppPalette.line.opacity(AppPalette.borderFaint), lineWidth: 1))
    }
}
```

- [ ] **Step 3: Add import preview summary and footer**

Add:

```swift
private var importPreviewSummary: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
        importCountChip("新增", dashboardSummary.importCounts.added, tint: AppPalette.positive)
        importCountChip("更新", dashboardSummary.importCounts.updated, tint: AppPalette.info)
        importCountChip("不变", dashboardSummary.importCounts.unchanged, tint: AppPalette.muted)
        importCountChip("重复", dashboardSummary.importCounts.duplicate, tint: AppPalette.warning)
        importCountChip("移除", dashboardSummary.importCounts.removed, tint: AppPalette.warning)
        importCountChip("阻塞", dashboardSummary.importCounts.blocked, tint: AppPalette.danger)
    }
}

private func importCountChip(_ title: String, _ count: Int, tint: Color) -> some View {
    HStack {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppPalette.muted)
        Spacer(minLength: 0)
        Text("\(count)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
    }
    .padding(AppPalette.spaceS)
    .background(tint.opacity(AppPalette.accentFill), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    .overlay(RoundedRectangle(cornerRadius: AppPalette.controlRadius).stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1))
}

private var importActionFooter: some View {
    HStack(spacing: AppPalette.spaceS) {
        Button {
            model.confirmActiveImportPreview()
        } label: {
            Label("确认写入", systemImage: "checkmark.circle")
        }
        .disabled(model.activeImportPreviewSession?.canConfirm != true)
        .buttonStyle(.borderedProminent)
        .tint(AppPalette.brand)

        if model.activeImportPreviewSession?.canConfirm != true {
            Text(dashboardSummary.importCounts.blocked > 0 ? "存在阻塞项，暂不能写入" : "请先生成有效预览")
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
        }

        Spacer(minLength: 0)

        Button(role: .destructive) {
            model.undoLatestImport()
        } label: {
            Label("撤销上次导入", systemImage: "arrow.uturn.backward")
        }
        .disabled(!model.canUndoLatestImport)
    }
}
```

- [ ] **Step 4: Sort import diff groups by severity**

In `importPreviewRows(_:)`, replace `ForEach(ImportPreviewChangeKind.allCases, id: \.self)` with:

```swift
ForEach(importPreviewDisplayOrder, id: \.self) { kind in
```

Add:

```swift
private var importPreviewDisplayOrder: [ImportPreviewChangeKind] {
    [.blocked, .duplicate, .removed, .updated, .added, .unchanged]
}
```

- [ ] **Step 5: Build**

Run:

```bash
swift build --package-path macos-app --build-tests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Views/EnhancementCenterView.swift
git commit -m "feat: refine enhancement import review"
```

---

### Task 6: Insight Panel Matrix And Final Verification

**Files:**
- Modify: `macos-app/Views/EnhancementCenterView.swift`

- [ ] **Step 1: Replace `insightPanel`**

Replace the existing `insightPanel` with:

```swift
private var insightPanel: some View {
    SectionCard(title: "洞察", subtitle: model.portfolioSnapshotInsightSummary.headline, icon: "chart.xyaxis.line") {
        VStack(alignment: .leading, spacing: AppPalette.spaceM) {
            insightReadinessStrip
            if model.portfolioSnapshotInsightSummary.hasEnoughHistory {
                insightMetricMatrix
            } else {
                insufficientInsightState
            }
        }
    }
}
```

- [ ] **Step 2: Add readiness strip and metric matrix**

Add:

```swift
private var insightReadinessStrip: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
        compactFact("快照数量", "\(model.portfolioInsightSnapshots.count) 次", tint: model.portfolioInsightSnapshots.count >= 2 ? AppPalette.positive : AppPalette.info)
        compactFact("洞察状态", model.portfolioSnapshotInsightSummary.hasEnoughHistory ? "已生成" : "待快照", tint: model.portfolioSnapshotInsightSummary.hasEnoughHistory ? AppPalette.positive : AppPalette.warning)
        compactFact("当前结论", model.portfolioSnapshotInsightSummary.headline, tint: AppPalette.info)
    }
}

private var insightMetricMatrix: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: AppPalette.spaceS)], spacing: AppPalette.spaceS) {
        ForEach(model.portfolioSnapshotInsightSummary.cards) { card in
            insightCard(card)
        }
    }
}
```

- [ ] **Step 3: Add insufficient history action state**

Add:

```swift
private var insufficientInsightState: some View {
    VStack(alignment: .leading, spacing: AppPalette.spaceM) {
        emptyState("快照不足", detail: "至少需要两次组合快照才能生成变化洞察。当前已有 \(model.portfolioInsightSnapshots.count) 次。")
        Button {
            model.recordPortfolioInsightSnapshotIfPossible()
        } label: {
            Label("记录当前快照", systemImage: "camera.metering.center.weighted")
        }
        .buttonStyle(.borderedProminent)
        .tint(AppPalette.brand)
        .disabled(model.personalAssetRows.isEmpty)
    }
}
```

- [ ] **Step 4: Improve `insightCard(_:)` hierarchy**

Update `insightCard(_:)` so it uses a stable 116pt height and a visible icon-like tone marker:

```swift
private func insightCard(_ card: PortfolioSnapshotInsightCard) -> some View {
    VStack(alignment: .leading, spacing: AppPalette.spaceS) {
        HStack {
            Text(card.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
            Spacer(minLength: 0)
            Circle()
                .fill(tint(for: card.tone))
                .frame(width: 8, height: 8)
        }
        Text(card.metric)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint(for: card.tone))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        Text(card.detail)
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
            .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
    .padding(AppPalette.spaceM)
    .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    .overlay(RoundedRectangle(cornerRadius: AppPalette.cardRadius).stroke(tint(for: card.tone).opacity(0.18), lineWidth: 1))
}
```

- [ ] **Step 5: Run all focused and broad tests**

Run:

```bash
swift test --package-path macos-app --filter EnhancementDashboardPresentationTests
swift build --package-path macos-app --build-tests
rm -rf /tmp/qieman-xctest-enhancement-redesign
mkdir -p /tmp/qieman-xctest-enhancement-redesign
cp -R macos-app/.build/arm64-apple-macosx/debug/QiemanDashboardPackageTests.xctest /tmp/qieman-xctest-enhancement-redesign/
mkdir -p /tmp/qieman-xctest-enhancement-redesign/QiemanDashboardPackageTests.xctest/Contents/Resources
codesign --force --sign - --deep /tmp/qieman-xctest-enhancement-redesign/QiemanDashboardPackageTests.xctest
xcrun xctest /tmp/qieman-xctest-enhancement-redesign/QiemanDashboardPackageTests.xctest
APP_VERSION=2.8.2 SIGN_IDENTITY="-" TARGET_ARCH=arm64 bash scripts/build_macos_app.sh
```

Expected:

- Focused presentation tests PASS.
- Full XCTest bundle PASS.
- Local app build prints `✅ 构建产物验证通过`.
- `spctl` may report ad-hoc signing rejection; that is expected for local builds.

- [ ] **Step 6: Commit**

```bash
git add macos-app/Views/EnhancementCenterView.swift
git commit -m "feat: refine enhancement insight panel"
```

- [ ] **Step 7: Final status check**

Run:

```bash
git status --short --branch
git log --oneline -8
```

Expected: clean worktree on `codex/enhancement-center-redesign`, with the plan commit plus implementation commits.
