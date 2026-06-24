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
        model.trendSettings = makeAgentSettings()
        model.trendAgentRunner = FakeTrendAgentRunner(
            reportJSON: TrendAnalysisReport.fixture(
                generatedAt: "2026-06-22 12:00:00",
                externalSignalStatus: .available
            ).jsonString()
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
        model.trendSettings = makeAgentSettings()
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
        model.trendAgentRunner = FakeTrendAgentRunner(reportJSON: invalid.jsonString())

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .rejected)
        XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-21 12:00:00")
        XCTAssertFalse(model.lastTrendError.isEmpty)
    }

    func testDailyAutoAnalysisRunsOnlyOncePerDay() async {
        let model = AppModel()
        model.trendSettings = makeAgentSettings(dailyAutoAnalysisEnabled: true)
        let runner = CountingTrendAgentRunner()
        model.trendAgentRunner = runner

        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 09:00:00")
        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 15:00:00")

        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(model.trendSettings.lastAutoAnalysisDay, "2026-06-22")
    }

    func testLargePortfolioGenerationUsesSingleAgentPacket() async {
        let model = AppModel()
        model.trendSettings = makeAgentSettings()
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
        let runner = CountingTrendAgentRunner()
        model.trendAgentRunner = runner

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .succeeded)
        XCTAssertEqual(runner.callCount, 1)
        let logMessages = model.trendProgressLogs.map(\.message).joined(separator: "\n")
        XCTAssertTrue(logMessages.contains("构建趋势上下文"))
        XCTAssertTrue(logMessages.contains("启动本地 Agent"))
        XCTAssertTrue(logMessages.contains("趋势分析完成"))
    }

    func testSlowTrendGenerationEmitsWaitingHeartbeatBeforeCompletion() async {
        let model = AppModel()
        model.trendProgressHeartbeatIntervalNanoseconds = 20_000_000
        model.trendSettings = makeAgentSettings()
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
        model.trendAgentRunner = SlowTrendAgentRunner(delayNanoseconds: 90_000_000)

        let generationTask = Task {
            await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")
        }
        try? await Task.sleep(nanoseconds: 55_000_000)

        let inFlightMessages = model.trendProgressLogs.map(\.message).joined(separator: "\n")
        XCTAssertEqual(model.trendGenerationState, .generating)
        XCTAssertTrue(inFlightMessages.contains("启动本地 Agent"))
        XCTAssertTrue(inFlightMessages.contains("等待 Agent 返回"))

        await generationTask.value
        XCTAssertEqual(model.trendGenerationState, .succeeded)
    }

    func testTrendConnectionCheckUpdatesSuccessState() async {
        let model = AppModel()
        model.trendSettings = makeAgentSettings()
        model.trendAgentRunner = FakeTrendAgentRunner(
            checkResult: TrendAgentCheckResult(
                agentName: "Fake",
                commandPath: "/tmp/fake-agent",
                preview: "OK"
            )
        )

        await model.checkTrendAgentConnection()

        XCTAssertEqual(model.trendConnectionState, .succeeded)
        XCTAssertTrue(model.lastTrendConnectionMessage.contains("Agent 可用"))
        XCTAssertEqual(model.lastTrendError, "")
    }

    func testTrendConnectionCheckFailsWhenAgentIsUnavailable() async {
        let model = AppModel()

        await model.checkTrendAgentConnection()

        XCTAssertEqual(model.trendConnectionState, .failed)
        XCTAssertTrue(model.lastTrendConnectionMessage.contains("未找到可运行"))
    }
}

private func makeAgentSettings(dailyAutoAnalysisEnabled: Bool = false) -> TrendAnalysisSettings {
    TrendAnalysisSettings(
        agent: TrendAgentSettings(
            kind: .custom,
            commandPath: "/tmp/fake-agent",
            model: "",
            profile: "",
            timeoutSeconds: 30,
            customCommandTemplate: ""
        ),
        defaultPrivacyMode: .sanitized,
        dailyAutoAnalysisEnabled: dailyAutoAnalysisEnabled,
        lastAutoAnalysisDay: nil
    )
}

private struct FakeTrendAgentRunner: TrendAgentRunnerProtocol {
    var reportJSON: String = TrendAnalysisReport.fixture(
        generatedAt: "2026-06-22 12:00:00",
        externalSignalStatus: .available
    ).jsonString()
    var checkResult = TrendAgentCheckResult(
        agentName: "Fake",
        commandPath: "/tmp/fake-agent",
        preview: "OK"
    )

    func generateReport(
        packet: TrendRunPacket,
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentRunResult {
        TrendAgentRunResult(
            reportJSON: reportJSON,
            agentName: "Fake",
            commandPath: "/tmp/fake-agent",
            durationSeconds: 0.1
        )
    }

    func check(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentCheckResult {
        checkResult
    }
}

private final class CountingTrendAgentRunner: TrendAgentRunnerProtocol {
    var callCount = 0
    var packets: [TrendRunPacket] = []

    func generateReport(
        packet: TrendRunPacket,
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentRunResult {
        callCount += 1
        packets.append(packet)
        return TrendAgentRunResult(
            reportJSON: TrendAnalysisReport.fixture(
                generatedAt: "2026-06-22 09:00:00",
                externalSignalStatus: .available
            ).jsonString(),
            agentName: "Counting",
            commandPath: "/tmp/fake-agent",
            durationSeconds: 0.1
        )
    }

    func check(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentCheckResult {
        TrendAgentCheckResult(agentName: "Counting", commandPath: "/tmp/fake-agent", preview: "OK")
    }
}

private struct SlowTrendAgentRunner: TrendAgentRunnerProtocol {
    let delayNanoseconds: UInt64

    func generateReport(
        packet: TrendRunPacket,
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentRunResult {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return TrendAgentRunResult(
            reportJSON: TrendAnalysisReport.fixture(
                generatedAt: "2026-06-22 12:00:00",
                externalSignalStatus: .available
            ).jsonString(),
            agentName: "Slow",
            commandPath: "/tmp/fake-agent",
            durationSeconds: 0.09
        )
    }

    func check(
        settings: TrendAgentSettings,
        candidates: [TrendAgentCandidate]
    ) async throws -> TrendAgentCheckResult {
        TrendAgentCheckResult(agentName: "Slow", commandPath: "/tmp/fake-agent", preview: "OK")
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
