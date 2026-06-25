import XCTest
@testable import QiemanDashboard

@MainActor
final class TrendAnalysisAppModelTests: XCTestCase {
    func testSuccessfulGenerationStoresReport() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings()
        model.trendAIClient = FakeTrendAIClient(
            report: TrendAnalysisReport.fixture(
                generatedAt: "2026-06-22 12:00:00",
                externalSignalStatus: .available
            )
        )

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .succeeded)
        XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-22 12:00:00")
    }

    func testRejectedGenerationKeepsLastSuccessfulReport() async {
        let model = AppModel()
        let previous = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-21 12:00:00",
            externalSignalStatus: .available
        )
        model.trendReport = previous
        model.trendSettings = makeProviderSettings()
        let invalid = previous.replacingActions([
            TrendActionCandidate(
                id: "bad",
                kind: .considerIncrease,
                title: "必须买入",
                detail: "保证收益",
                targetName: nil,
                confidence: TrendConfidence(score: 99, label: "高"),
                triggerConditions: ["任意条件"],
                invalidatingConditions: ["任意反证"]
            )
        ])
        model.trendAIClient = FakeTrendAIClient(report: invalid)

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .rejected)
        XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-21 12:00:00")
        XCTAssertFalse(model.lastTrendError.isEmpty)
    }

    func testDailyAutoAnalysisRunsOnlyOncePerDay() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings(dailyAutoAnalysisEnabled: true)
        let client = CountingTrendAIClient()
        model.trendAIClient = client

        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 09:00:00")
        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 15:00:00")

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(model.trendSettings.lastAutoAnalysisDay, "2026-06-22")
    }

    func testLargePortfolioGenerationUsesSingleModelRequest() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings()
        var rows: [PersonalAssetAggregateRow] = []
        for index in 0..<41 {
            let row = trendAggregateRow(
                code: String(format: "51%04d", index),
                name: "测试基金\(index)",
                marketValue: 100_000 - Double(index * 1_000),
                costValue: 90_000 - Double(index * 800),
                profitAmount: 10_000 - Double(index * 200),
                profitPct: 10 - Double(index) * 0.2,
                estimateChangePct: Double(index % 5) * 0.1
            )
            rows.append(row)
        }
        model.personalAssetRows = rows
        let client = CountingTrendAIClient()
        model.trendAIClient = client

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .succeeded)
        XCTAssertEqual(client.callCount, 1)
        let logMessages = model.trendProgressLogs.map(\.message).joined(separator: "\n")
        XCTAssertTrue(logMessages.contains("构建趋势上下文"))
        XCTAssertTrue(logMessages.contains("启动趋势模型"))
        XCTAssertTrue(logMessages.contains("趋势分析完成"))
    }

    func testGenerationLogsExplainableTraceWithoutClaimingModelThoughts() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings()
        model.personalAssetRows = [
            trendAggregateRow(
                code: "510300",
                name: "沪深300ETF",
                marketValue: 10_000,
                costValue: 9_500,
                profitAmount: 500,
                profitPct: 5.26,
                estimateChangePct: 0.2
            )
        ]
        model.trendAIClient = FakeTrendAIClient()

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertTrue(model.trendProgressLogs.contains(where: { log in
            log.message.contains("输入摘要") && (log.detail?.contains("沪深300ETF") == true)
        }))
        XCTAssertTrue(model.trendProgressLogs.contains(where: { log in
            log.message.contains("提示词摘要") && (log.detail?.contains("system") == true)
        }))
        XCTAssertTrue(model.trendProgressLogs.contains(where: { log in
            log.message.contains("模型输出摘要") && (log.detail?.contains("keyAssets") == true)
        }))
        XCTAssertTrue(model.trendProgressLogs.contains(where: { log in
            log.message.contains("JSON 校验通过") && (log.detail?.contains("可展示") == true)
        }))
        let allVisibleLogText = model.trendProgressLogs
            .map { "\($0.message)\n\($0.detail ?? "")" }
            .joined(separator: "\n")
        XCTAssertFalse(allVisibleLogText.contains("模型思考过程"))
    }

    func testSlowTrendGenerationEmitsWaitingHeartbeatBeforeCompletion() async {
        let model = AppModel()
        model.trendProgressHeartbeatIntervalNanoseconds = 20_000_000
        model.trendSettings = makeProviderSettings()
        model.personalAssetRows = [
            trendAggregateRow(
                code: "510300",
                name: "沪深300ETF",
                marketValue: 10_000,
                costValue: 9_500,
                profitAmount: 500,
                profitPct: 5.26,
                estimateChangePct: 0.2
            )
        ]
        model.trendAIClient = SlowTrendAIClient(delayNanoseconds: 90_000_000)

        let generationTask = Task {
            await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")
        }
        try? await Task.sleep(nanoseconds: 55_000_000)

        let inFlightMessages = model.trendProgressLogs.map(\.message).joined(separator: "\n")
        XCTAssertEqual(model.trendGenerationState, .generating)
        XCTAssertTrue(inFlightMessages.contains("启动趋势模型"))
        XCTAssertTrue(inFlightMessages.contains("等待模型返回"))

        await generationTask.value
        XCTAssertEqual(model.trendGenerationState, .succeeded)
    }

    func testTrendConnectionCheckUpdatesSuccessState() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings()
        model.trendAIClient = FakeTrendAIClient(
            checkResult: TrendConnectionCheckResult(
                endpoint: "https://api.example.com/v1/chat/completions",
                model: "glm-5.2",
                preview: "OK"
            )
        )

        await model.checkTrendAIConnection()

        XCTAssertEqual(model.trendConnectionState, .succeeded)
        XCTAssertTrue(model.lastTrendConnectionMessage.contains("模型可用"))
        XCTAssertEqual(model.lastTrendError, "")
    }

    func testTrendConnectionCheckPersistsCurrentSettingsBeforeRequest() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel()
        model.dataDirectoryURL = directory
        model.trendSettings = makeProviderSettings()
        model.trendSettings.provider.model = "glm-5-turbo"
        model.trendAIClient = FakeTrendAIClient()

        await model.checkTrendAIConnection()

        let saved = try TrendAnalysisSettingsStore().load(
            from: directory.appendingPathComponent("trend-analysis-settings.json")
        )
        XCTAssertEqual(saved.provider.model, "glm-5-turbo")
        XCTAssertEqual(saved.provider.baseURL, "https://api.example.com/v1")
    }

    func testTrendConnectionCheckFailsWhenProviderIsUnavailable() async {
        let model = AppModel()

        await model.checkTrendAIConnection()

        XCTAssertEqual(model.trendConnectionState, .failed)
        XCTAssertTrue(model.lastTrendConnectionMessage.contains("尚未配置趋势分析模型"))
    }

    func testTrendDashboardSummaryReflectsCurrentTrendState() {
        let model = AppModel()
        let generatedAt = "\(String(AppModel.timestampString().prefix(10))) 09:30:00"
        let report = TrendAnalysisReport.fixture(
            generatedAt: generatedAt,
            externalSignalStatus: .available
        )
        model.trendSettings = makeProviderSettings()
        model.trendReport = report
        model.lastTrendGeneratedAt = report.generatedAt
        model.trendGenerationState = .succeeded

        let summary = model.trendDashboardSummary

        XCTAssertEqual(summary.status, .ready)
        XCTAssertEqual(summary.headline, report.portfolio.headline)
        XCTAssertEqual(summary.primaryAction.kind, .openReport)
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("trend-appmodel-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeProviderSettings(dailyAutoAnalysisEnabled: Bool = false) -> TrendAnalysisSettings {
    TrendAnalysisSettings(
        provider: TrendAIProviderSettings(
            providerName: "Test",
            baseURL: "https://api.example.com/v1",
            model: "glm-5.2",
            apiKey: "sk-test",
            supportsOnlineSearch: true,
            timeoutSeconds: 30
        ),
        defaultPrivacyMode: .sanitized,
        dailyAutoAnalysisEnabled: dailyAutoAnalysisEnabled,
        lastAutoAnalysisDay: nil
    )
}

private struct FakeTrendAIClient: TrendAIClientProtocol {
    var report = TrendAnalysisReport.fixture(
        generatedAt: "2026-06-22 12:00:00",
        externalSignalStatus: .available
    )
    var checkResult = TrendConnectionCheckResult(
        endpoint: "https://api.example.com/v1/chat/completions",
        model: "glm-5.2",
        preview: "OK"
    )

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        report
    }

    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult {
        checkResult
    }
}

private final class CountingTrendAIClient: TrendAIClientProtocol {
    var callCount = 0
    var prompts: [TrendModelPrompt] = []

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        callCount += 1
        prompts.append(prompt)
        return TrendAnalysisReport.fixture(
            generatedAt: "2026-06-22 09:00:00",
            externalSignalStatus: .available
        )
    }

    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult {
        TrendConnectionCheckResult(
            endpoint: "https://api.example.com/v1/chat/completions",
            model: settings.model,
            preview: "OK"
        )
    }
}

private struct SlowTrendAIClient: TrendAIClientProtocol {
    let delayNanoseconds: UInt64

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return TrendAnalysisReport.fixture(
            generatedAt: "2026-06-22 12:00:00",
            externalSignalStatus: .available
        )
    }

    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult {
        TrendConnectionCheckResult(
            endpoint: "https://api.example.com/v1/chat/completions",
            model: settings.model,
            preview: "OK"
        )
    }
}

private extension TrendAnalysisReport {
    func jsonString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(self)
        return String(data: data, encoding: .utf8)!
    }
}

private func trendAggregateRow(
    code: String,
    name: String,
    assetType: PersonalAssetType = .fund,
    stockMarket: StockMarket? = nil,
    fundMarket: FundMarket? = .onExchange,
    marketValue: Double,
    costValue: Double,
    profitAmount: Double,
    profitPct: Double,
    estimateChangePct: Double
) -> PersonalAssetAggregateRow {
    let units = 100.0
    let holding = UserPortfolioHolding(
        fundCode: code,
        assetType: assetType,
        units: units,
        costPrice: costValue / units,
        displayName: name,
        stockMarket: stockMarket,
        fundMarket: assetType == .fund ? fundMarket : nil
    )
    let valuation = UserPortfolioValuationRow(
        holding: holding,
        fundName: name,
        currentPrice: marketValue / units,
        priceTime: "2026-06-22 10:00:00",
        priceSource: "测试估值",
        officialNav: nil,
        officialNavDate: nil,
        estimatePrice: marketValue / units,
        estimatePriceTime: "2026-06-22 10:00:00",
        marketValue: marketValue,
        costValue: costValue,
        profitAmount: profitAmount,
        profitPct: profitPct,
        estimateChangePct: estimateChangePct
    )
    return PersonalAssetAggregateRow(
        key: "\(assetType.rawValue)-\(code)",
        assetType: assetType,
        fundName: name,
        fundCode: code,
        holdingRow: valuation,
        rawHolding: holding,
        archivedHolding: nil,
        pendingTrades: [],
        plans: []
    )
}
