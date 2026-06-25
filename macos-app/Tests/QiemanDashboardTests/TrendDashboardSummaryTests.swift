import XCTest
@testable import QiemanDashboard

final class TrendDashboardSummaryTests: XCTestCase {
    func testUnconfiguredProviderShowsSettingsAction() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: false,
                generationState: .idle,
                lastGeneratedAt: nil,
                headline: "尚未配置趋势分析模型",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .idle,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .unconfigured)
        XCTAssertEqual(summary.headline, "尚未配置趋势分析模型")
        XCTAssertEqual(summary.primaryAction.kind, .configure)
        XCTAssertEqual(summary.primaryAction.title, "配置模型")
        XCTAssertTrue(summary.horizons.isEmpty)
        XCTAssertTrue(summary.sectors.isEmpty)
    }

    func testConfiguredProviderWithoutReportShowsGenerateAction() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .idle,
                lastGeneratedAt: nil,
                headline: "等待生成趋势分析",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .idle,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .empty)
        XCTAssertEqual(summary.primaryAction.kind, .generate)
        XCTAssertEqual(summary.primaryAction.title, "立即分析")
        XCTAssertNil(summary.secondaryAction)
    }

    func testGeneratedReportExtractsHeadlineRiskHorizonsAndSectors() {
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-25 09:30:00",
            externalSignalStatus: .available
        )
        let summary = TrendDashboardSummary.make(
            report: report,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .succeeded,
                lastGeneratedAt: report.generatedAt,
                headline: report.portfolio.headline,
                externalSignalStatus: report.externalSignalStatus,
                isStale: false
            ),
            generationState: .succeeded,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.headline, report.portfolio.headline)
        XCTAssertEqual(summary.riskText, report.portfolio.riskLevel.dashboardText)
        XCTAssertEqual(summary.primaryAction.kind, .openReport)
        XCTAssertEqual(summary.secondaryAction?.kind, .refresh)
        XCTAssertEqual(summary.horizons.map(\.title), ["短期", "中期", "长期"])
        XCTAssertEqual(summary.sectors.count, min(4, report.sectors.count))
        XCTAssertEqual(summary.dataAsOf, report.dataAsOf)
        XCTAssertEqual(summary.externalSignalText, "外部信号可用")
    }

    func testGeneratedReportKeepsPortfolioSummaryReadableForWideOverview() {
        let longDetail = "当前组合包含 26 只场外基金，总市值约 37.29 万元。组合在科技与海外资产上积累了丰厚的浮盈，消费与白酒板块短期承压但仍需结合计划节奏复核。"
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-25 09:30:00",
            externalSignalStatus: .available
        )
        .replacingPortfolio(
            TrendPortfolioSummary(
                headline: "组合整体盈利稳固，结构上呈现科技/海外领涨",
                riskLevel: .medium,
                summary: longDetail
            )
        )

        let summary = TrendDashboardSummary.make(
            report: report,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .succeeded,
                lastGeneratedAt: report.generatedAt,
                headline: report.portfolio.headline,
                externalSignalStatus: report.externalSignalStatus,
                isStale: false
            ),
            generationState: .succeeded,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.detail, longDetail)
    }

    func testStaleReportMarksRefreshAsPrimaryAction() {
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-24 09:30:00",
            externalSignalStatus: .partial
        )
        let summary = TrendDashboardSummary.make(
            report: report,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .succeeded,
                lastGeneratedAt: report.generatedAt,
                headline: report.portfolio.headline,
                externalSignalStatus: report.externalSignalStatus,
                isStale: true
            ),
            generationState: .succeeded,
            lastError: "",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(summary.stateText, "待更新")
        XCTAssertEqual(summary.primaryAction.kind, .refresh)
        XCTAssertEqual(summary.secondaryAction?.kind, .openReport)
    }

    func testFailedGenerationKeepsRecoveryActionAndShortError() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .failed,
                lastGeneratedAt: nil,
                headline: "模型请求失败",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .failed,
            lastError: "趋势分析模型请求失败：HTTP 429。服务商提示余额不足或无可用资源包。",
            progressLogs: []
        )

        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.primaryAction.kind, .refresh)
        XCTAssertTrue(summary.detail.contains("HTTP 429"))
        XCTAssertLessThanOrEqual(summary.detail.count, 48)
    }

    func testGeneratingStateUsesLatestProgressLogAndDisablesPrimaryAction() {
        let summary = TrendDashboardSummary.make(
            report: nil,
            trendStatus: EnhancementTrendStatus(
                isProviderConfigured: true,
                generationState: .generating,
                lastGeneratedAt: nil,
                headline: "等待模型返回",
                externalSignalStatus: nil,
                isStale: false
            ),
            generationState: .generating,
            lastError: "",
            progressLogs: [
                TrendProgressLog(timestamp: "2026-06-25 09:30:00", message: "启动趋势模型"),
                TrendProgressLog(timestamp: "2026-06-25 09:31:00", message: "等待模型返回：模型分析 已等待 1m")
            ]
        )

        XCTAssertEqual(summary.status, .generating)
        XCTAssertEqual(summary.primaryAction.kind, .wait)
        XCTAssertTrue(summary.primaryAction.isDisabled)
        XCTAssertEqual(summary.detail, "等待模型返回：模型分析 已等待 1m")
    }

    func testOverviewSourceRendersAITrendSummaryPanel() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/OverviewSectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("AITrendSummaryPanel("))
        XCTAssertTrue(source.contains("summary: model.trendDashboardSummary"))
        XCTAssertTrue(source.contains("model.selectedEnhancementTab = .trend"))
        XCTAssertTrue(source.contains("await model.generateTrendAnalysis(userInitiated: true)"))
    }

    func testOverviewSourceMergesSummaryIntoTodayBrief() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/OverviewSectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("summaryItems: overviewBriefSummaryItems"))
        XCTAssertTrue(source.contains("TodayBriefSummaryCard("))
        XCTAssertFalse(source.contains("OverviewHeroCard()"))
        XCTAssertFalse(source.contains("struct OverviewHeroCard"))
        XCTAssertFalse(source.contains("今日看板"))
        XCTAssertFalse(source.contains("总览摘要"))
    }

    func testOverviewSourceUsesFullWidthGridsAndDropsAssetOverview() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/OverviewSectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("SectionCard(title: \"资产总览\""))
        XCTAssertFalse(source.contains("OverviewAssetTypeSummary"))
        XCTAssertFalse(source.contains("assetTypeSummary"))
        XCTAssertTrue(source.contains("todayBriefWideColumns"))
        XCTAssertTrue(source.contains("trendHorizonWideColumns"))
        XCTAssertTrue(source.contains("trendSectorWideColumns"))
        XCTAssertTrue(source.contains(".lineLimit(4)"))
        XCTAssertTrue(source.contains(".lineLimit(3)"))
    }

    func testOverviewSourceDropsManagerActivityAndFreshnessPanels() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/OverviewSectionView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("DashboardInsightPanel("))
        XCTAssertFalse(source.contains("struct DashboardInsightPanel"))
        XCTAssertFalse(source.contains("ManagerActivityPanel"))
        XCTAssertFalse(source.contains("FreshnessStatusPanel"))
        XCTAssertFalse(source.contains("openManagerActivity"))
        XCTAssertFalse(source.contains("openFreshness"))
        XCTAssertFalse(source.contains("主理人动态"))
        XCTAssertFalse(source.contains("数据状态"))
    }

    func testTrendPanelSourceUsesRoomierReportLayoutAndCompactProgressLog() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/EnhancementTrendPanel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("trendReportResponsiveLayout"))
        XCTAssertTrue(source.contains("trendReportPrimaryColumn"))
        XCTAssertTrue(source.contains("trendReportSidebarColumn"))
        XCTAssertTrue(source.contains("trendProgressSummaryCard"))
        XCTAssertTrue(source.contains("model.trendProgressLogs.suffix(6)"))
        XCTAssertFalse(source.contains("model.trendProgressLogs.suffix(16)"))
    }
}

private extension TrendAnalysisReport {
    func replacingPortfolio(_ portfolio: TrendPortfolioSummary) -> TrendAnalysisReport {
        TrendAnalysisReport(
            id: id,
            generatedAt: generatedAt,
            dataAsOf: dataAsOf,
            privacyMode: privacyMode,
            externalSignalStatus: externalSignalStatus,
            portfolio: portfolio,
            horizons: horizons,
            sectors: sectors,
            keyAssets: keyAssets,
            actions: actions,
            evidence: evidence,
            warnings: warnings,
            disclaimer: disclaimer
        )
    }
}
