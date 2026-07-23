import XCTest
@testable import QiemanDashboard

final class PersonalAssetBrowserPresentationTests: XCTestCase {
    func testPortfolioSectionNoLongerRendersMonthlyReportPanel() throws {
        let source = try String(contentsOf: portfolioSectionSourceURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("MonthlyReportPanel(summary:"))
        XCTAssertFalse(source.contains("didCopyMonthlyReport"))
        XCTAssertFalse(source.contains("private func copyMonthlyReport"))
    }

    func testPortfolioSectionOmitsReminderAndPlanSimulationPanels() throws {
        let source = try String(contentsOf: portfolioSectionSourceURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("PortfolioReminderPanel("))
        XCTAssertFalse(source.contains("PlanSimulationPanel("))
        XCTAssertFalse(source.contains("SectionCard(title: \"提醒通知\""))
        XCTAssertFalse(source.contains("SectionCard(title: \"计划模拟\""))
    }

    func testPortfolioSectionFillsWideSummaryAndDiagnosticCards() throws {
        let source = try String(contentsOf: portfolioSectionSourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("portfolioSummaryWideColumns"))
        XCTAssertTrue(source.contains("portfolioSummaryMediumColumns"))
        XCTAssertTrue(source.contains("portfolioDiagnosticWideColumns"))
        XCTAssertTrue(source.contains("portfolioDiagnosticMediumColumns"))
        XCTAssertTrue(source.contains("LazyVGrid(columns: portfolioSummaryWideColumns"))
        XCTAssertTrue(source.contains("LazyVGrid(columns: portfolioDiagnosticWideColumns"))
        XCTAssertFalse(source.contains("LazyVGrid(columns: [GridItem(.adaptive(minimum: 220)"))
        XCTAssertFalse(source.contains("LazyVGrid(columns: [GridItem(.adaptive(minimum: 168)"))
    }

    func testPersonalAssetTableUsesNaturalVerticalHeight() throws {
        let source = try String(contentsOf: personalAssetBrowserSourceURL(), encoding: .utf8)

        XCTAssertFalse(source.contains(".frame(height: tableHeightEstimate)"))
        XCTAssertFalse(source.contains("private var tableHeightEstimate"))
        XCTAssertFalse(source.contains("PersonalAssetTableLayout"))
    }

    func testPersonalAssetTableFillsWideWindows() throws {
        let browserSource = try String(contentsOf: personalAssetBrowserSourceURL(), encoding: .utf8)
        let rowSource = try String(contentsOf: personalAssetTableRowSourceURL(), encoding: .utf8)

        XCTAssertTrue(browserSource.contains("updateAvailableWidth(geometry.size.width)"))
        XCTAssertFalse(browserSource.contains("widthProbe"))
        XCTAssertFalse(browserSource.contains("PersonalAssetTableWidthPreferenceKey"))
        XCTAssertTrue(browserSource.contains("PersonalAssetTableColumnLayout.resolve("))
        XCTAssertTrue(browserSource.contains("AssetTableContainerFillModifier(isCompact: isCompact, tableWidth: layout.tableWidth)"))
        XCTAssertTrue(browserSource.contains("AssetTableLabelColumnModifier(isCompact: isCompact, minWidth: layout.labelWidth)"))
        XCTAssertTrue(browserSource.contains("labelWidth: layout.labelWidth"))
        XCTAssertFalse(browserSource.contains(".frame(width: layout.tableWidth, alignment: .leading)"))
        XCTAssertTrue(rowSource.contains("var labelWidth: CGFloat = 260"))
        XCTAssertTrue(rowSource.contains(".frame(width: labelWidth, alignment: .leading)"))
        XCTAssertTrue(rowSource.contains("AssetTableLabelColumnModifier(isCompact: isCompact, minWidth: labelWidth)"))
        XCTAssertTrue(rowSource.contains(".frame(maxWidth: .infinity, alignment: .leading)\n        .overlay(alignment: .leading)"))

        // compact 横向滚动保持固定宽度，常规宽度必须撑满容器避免右侧空白
        XCTAssertTrue(browserSource.contains("struct AssetTableContainerFillModifier"))
        XCTAssertTrue(browserSource.contains("content.frame(width: tableWidth, alignment: .leading)"))
        XCTAssertTrue(browserSource.contains("content.frame(maxWidth: .infinity, alignment: .leading)"))
    }

    func testPersonalAssetTableLayoutExpandsIntoWideContainer() {
        let layout = PersonalAssetTableColumnLayout.resolve(
            availableWidth: 1_720,
            fixedColumnsWidth: 1_044,
            minimumLabelWidth: 260
        )

        XCTAssertEqual(layout.tableWidth, 1_720)
        XCTAssertEqual(layout.labelWidth, 676)
    }

    func testPersonalAssetTableLayoutKeepsMinimumWidthForNarrowContainer() {
        let layout = PersonalAssetTableColumnLayout.resolve(
            availableWidth: 900,
            fixedColumnsWidth: 1_044,
            minimumLabelWidth: 260
        )

        XCTAssertEqual(layout.tableWidth, 1_304)
        XCTAssertEqual(layout.labelWidth, 260)
    }

    func testAssetDetailUsesAIOpinionCopyAndKeepsConditionsVisible() throws {
        let source = try String(contentsOf: personalAssetDetailSourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("detailSection(title: \"AI 观点\", icon: \"sparkles\")"))
        XCTAssertTrue(source.contains("trendTradePlanCard(summary.tradePlan)"))
        XCTAssertTrue(source.contains("trendTradePlanList(title: \"触发\""))
        XCTAssertTrue(source.contains("trendTradePlanList(title: \"反证\""))
        XCTAssertTrue(source.contains("Text(\"数据 \\(summary.dataAsOf)\""))
    }

    func testAssetDetailShowsInteractivePriceTrendBeforeSupportingSections() throws {
        let detailSource = try String(contentsOf: personalAssetDetailSourceURL(), encoding: .utf8)
        let chartSource = try String(contentsOf: personalAssetTrendChartSourceURL(), encoding: .utf8)

        XCTAssertTrue(detailSource.contains("PersonalAssetPriceTrendChart(row: row)"))
        XCTAssertTrue(chartSource.contains("import Charts"))
        XCTAssertTrue(chartSource.contains("Picker(\"走势区间\""))
        XCTAssertTrue(chartSource.contains(".onContinuousHover"))
        XCTAssertTrue(chartSource.contains("Label(\"虚线：持仓成本\""))
        XCTAssertTrue(chartSource.contains("model.platformClient.fetchPersonalAssetPriceHistory"))
    }

    func testTableRowKeepsOnlyNonRedundantAssetAndTrendMetadata() throws {
        let source = try String(contentsOf: personalAssetTableRowSourceURL(), encoding: .utf8)

        XCTAssertTrue(source.contains("if let trendSummary"))
        XCTAssertTrue(source.contains("trendSignalBlock(trendSummary)"))
        XCTAssertTrue(source.contains("summary.tradePlan.label"))
        XCTAssertTrue(source.contains("summary.primaryConfidence.label"))
        XCTAssertTrue(source.contains("Text(summary.tradePlan.method)"))
        XCTAssertTrue(source.contains("Text(\"·\")"))
        XCTAssertTrue(source.contains("Text(\"\\(summary.counterSignals.count) 条反证\")"))
        XCTAssertFalse(source.contains("private func trendTagChip"))
        XCTAssertTrue(source.contains("if row.assetType == .stock, let stockMarketLabel = row.detectedMarket?.displayName"))
        XCTAssertTrue(source.contains("ToolbarBadge(title: stockMarketLabel"))
        XCTAssertFalse(source.contains("rawHolding?.marketLabel"))
        XCTAssertFalse(source.contains("ToolbarBadge(title: row.combinedStatusText"))
        XCTAssertFalse(source.contains("Spacer(minLength: 4)\n                if !summary.counterSignals.isEmpty"))
        XCTAssertTrue(source.contains("ToolbarBadge(title: \"待确认\""))
        XCTAssertTrue(source.contains("ToolbarBadge(title: \"计划中\""))
    }

    func testPresentationBuildsCountsAndVisibleRowsFromScopeSearchAndSort() {
        let rows = [
            row(key: "wide", name: "沪深300", code: "000300", marketValue: 30_000, pendingAmount: 0),
            row(key: "dividend", name: "红利低波", code: "000922", marketValue: 10_000, pendingAmount: 500),
            row(key: "pending", name: "等待确认", code: "000001", marketValue: nil, pendingAmount: 800)
        ]

        let presentation = PersonalAssetBrowserPresentationModel.make(
            rows: rows,
            keyword: "000",
            filterScope: .pending,
            sortOption: .pendingAmount,
            comparisonSelection: ["pending", "wide"],
            comparisonMaxCount: 4
        )

        XCTAssertEqual(presentation.filterCounts[.all], 3)
        XCTAssertEqual(presentation.filterCounts[.holding], 2)
        XCTAssertEqual(presentation.filterCounts[.pending], 2)
        XCTAssertEqual(presentation.visibleRows.map(\.id), ["pending", "dividend"])
        XCTAssertEqual(presentation.comparisonSummary.items.map(\.id), ["pending", "wide"])
    }

    func testPresentationPrunesInvalidComparisonSelection() {
        let rows = [
            row(key: "wide", name: "沪深300", code: "000300", marketValue: 30_000, pendingAmount: 0)
        ]

        let presentation = PersonalAssetBrowserPresentationModel.make(
            rows: rows,
            keyword: "",
            filterScope: .all,
            sortOption: .name,
            comparisonSelection: ["missing", "wide"],
            comparisonMaxCount: 4
        )

        XCTAssertEqual(presentation.validComparisonSelection, ["wide"])
        XCTAssertEqual(presentation.comparisonSummary.items.map(\.id), ["wide"])
    }

    private func portfolioSectionSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PortfolioSectionView.swift")
    }

    private func personalAssetBrowserSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PersonalAssetBrowser.swift")
    }

    private func personalAssetDetailSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PersonalAsset/PersonalAssetDetailSheet.swift")
    }

    private func personalAssetTrendChartSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PersonalAsset/PersonalAssetPriceTrendChart.swift")
    }

    private func personalAssetTableRowSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Views/PersonalAsset/PersonalAssetTableRow.swift")
    }

    private func row(
        key: String,
        name: String,
        code: String,
        marketValue: Double?,
        pendingAmount: Double
    ) -> PersonalAssetAggregateRow {
        let holding = marketValue.map { _ in
            UserPortfolioHolding(fundCode: code, assetType: .fund, units: 10_000, costPrice: 1, displayName: name)
        }
        let valuationRow = holding.map {
            UserPortfolioValuationRow(
                holding: $0,
                fundName: name,
                currentPrice: nil,
                priceTime: nil,
                priceSource: nil,
                officialNav: nil,
                officialNavDate: nil,
                estimatePrice: nil,
                estimatePriceTime: nil,
                marketValue: marketValue,
                costValue: nil,
                profitAmount: nil,
                profitPct: nil,
                estimateChangePct: nil
            )
        }
        let pendingTrades = pendingAmount > 0
            ? [
                PersonalPendingTrade(
                    occurredAt: "2026-06-05",
                    actionLabel: "买入",
                    fundName: name,
                    fundCode: code,
                    amountText: "\(pendingAmount)",
                    amountValue: pendingAmount,
                    status: "待确认"
                )
            ]
            : []
        return PersonalAssetAggregateRow(
            key: key,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: valuationRow,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: pendingTrades,
            plans: []
        )
    }
}
