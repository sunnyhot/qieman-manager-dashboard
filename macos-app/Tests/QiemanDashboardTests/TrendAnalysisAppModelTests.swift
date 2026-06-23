import XCTest
@testable import QiemanDashboard

@MainActor
final class TrendAnalysisAppModelTests: XCTestCase {
    func testImportingLocalCandidateUpdatesSettings() {
        let model = AppModel()
        let candidate = LocalAIConfigurationCandidate(
            id: "env-openai",
            providerName: "OpenAI-compatible environment",
            sourceDescription: "Process environment",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4.1",
            apiKey: "sk-test",
            apiKeySource: "OPENAI_API_KEY",
            compatibility: .openAICompatible,
            confidence: 95,
            warning: nil
        )

        model.importTrendProvider(candidate)

        XCTAssertEqual(model.trendSettings.provider.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(model.trendSettings.provider.model, "gpt-4.1")
        XCTAssertEqual(model.trendSettings.provider.apiKey, "sk-test")
    }

    func testSuccessfulGenerationStoresReport() async {
        let model = AppModel()
        model.trendSettings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 30
            ),
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: false,
            lastAutoAnalysisDay: nil
        )
        model.trendAIClient = FakeTrendAIClient(
            report: .fixture(
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
        model.trendSettings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 30
            ),
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: false,
            lastAutoAnalysisDay: nil
        )
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
        model.trendSettings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 30
            ),
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: true,
            lastAutoAnalysisDay: nil
        )
        let client = CountingTrendAIClient()
        model.trendAIClient = client

        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 09:00:00")
        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 15:00:00")

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(model.trendSettings.lastAutoAnalysisDay, "2026-06-22")
    }

    func testLargePortfolioGenerationUsesChunkRequestsThenSynthesis() async {
        let model = AppModel()
        model.trendSettings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 300
            ),
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: false,
            lastAutoAnalysisDay: nil
        )
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
        XCTAssertEqual(client.callCount, 4)
        guard client.prompts.count == 4 else { return }
        XCTAssertTrue(client.prompts[0].user.contains("分块 1/3"))
        XCTAssertTrue(client.prompts[1].user.contains("分块 2/3"))
        XCTAssertTrue(client.prompts[2].user.contains("分块 3/3"))
        XCTAssertTrue(client.prompts[3].user.contains("分块报告"))
        let logMessages = model.trendProgressLogs.map(\.message).joined(separator: "\n")
        XCTAssertTrue(logMessages.contains("构建趋势上下文"))
        XCTAssertTrue(logMessages.contains("分块模式"))
        XCTAssertTrue(logMessages.contains("合成全组合报告"))
        XCTAssertTrue(logMessages.contains("趋势分析完成"))
    }

    func testTrendConnectionCheckUpdatesSuccessState() async {
        let model = AppModel()
        model.trendSettings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 30
            ),
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: false,
            lastAutoAnalysisDay: nil
        )
        model.trendAIClient = FakeTrendAIClient(
            report: .fixture(
                generatedAt: "2026-06-22 12:00:00",
                externalSignalStatus: .available
            ),
            connectionResult: TrendConnectionCheckResult(
                endpoint: "https://example.com/v1/chat/completions",
                model: "test-model",
                preview: "OK"
            )
        )

        await model.checkTrendAIConnection()

        XCTAssertEqual(model.trendConnectionState, .succeeded)
        XCTAssertTrue(model.lastTrendConnectionMessage.contains("连通正常"))
        XCTAssertEqual(model.lastTrendError, "")
    }

    func testTrendConnectionCheckFailsWhenProviderIsIncomplete() async {
        let model = AppModel()

        await model.checkTrendAIConnection()

        XCTAssertEqual(model.trendConnectionState, .failed)
        XCTAssertTrue(model.lastTrendConnectionMessage.contains("配置不完整"))
    }
}

private struct FakeTrendAIClient: TrendAIClientProtocol {
    var report: TrendAnalysisReport = .fixture(
        generatedAt: "2026-06-22 12:00:00",
        externalSignalStatus: .available
    )
    var connectionResult = TrendConnectionCheckResult(
        endpoint: "https://example.com/v1/chat/completions",
        model: "test-model",
        preview: "OK"
    )

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        report
    }

    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult {
        connectionResult
    }
}

private final class CountingTrendAIClient: TrendAIClientProtocol {
    var callCount = 0
    var prompts: [TrendModelPrompt] = []

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        callCount += 1
        prompts.append(prompt)
        return .fixture(
            generatedAt: "2026-06-22 09:00:00",
            externalSignalStatus: .available
        )
    }

    func checkConnection(settings: TrendAIProviderSettings) async throws -> TrendConnectionCheckResult {
        TrendConnectionCheckResult(
            endpoint: "https://example.com/v1/chat/completions",
            model: settings.model,
            preview: "OK"
        )
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
