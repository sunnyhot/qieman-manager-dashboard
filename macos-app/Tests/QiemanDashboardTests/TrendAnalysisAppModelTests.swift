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

    func generateReport(prompt: TrendModelPrompt, settings: TrendAIProviderSettings) async throws -> TrendAnalysisReport {
        callCount += 1
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
