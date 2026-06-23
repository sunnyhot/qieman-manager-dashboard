import XCTest
@testable import QiemanDashboard

final class TrendAnalysisStoreTests: XCTestCase {
    func testSettingsStoreReturnsDefaultWhenFileIsMissing() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("trend-settings.json")

        let settings = try TrendAnalysisSettingsStore().load(from: url)

        XCTAssertEqual(settings.provider.baseURL, "")
        XCTAssertEqual(settings.provider.model, "")
        XCTAssertEqual(settings.defaultPrivacyMode, .sanitized)
        XCTAssertFalse(settings.dailyAutoAnalysisEnabled)
    }

    func testSettingsStoreSavesAndLoadsProviderSettings() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("trend-settings.json")
        let settings = TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "OpenRouter",
                baseURL: "https://openrouter.ai/api",
                model: "perplexity/sonar",
                apiKey: "sk-test-value",
                supportsOnlineSearch: true,
                timeoutSeconds: 45
            ),
            defaultPrivacyMode: .fullDetail,
            dailyAutoAnalysisEnabled: true,
            lastAutoAnalysisDay: "2026-06-22"
        )

        try TrendAnalysisSettingsStore().save(settings, to: url)
        let loaded = try TrendAnalysisSettingsStore().load(from: url)

        XCTAssertEqual(loaded.provider.providerName, settings.provider.providerName)
        XCTAssertEqual(loaded.provider.baseURL, settings.provider.baseURL)
        XCTAssertEqual(loaded.provider.model, settings.provider.model)
        XCTAssertEqual(loaded.provider.apiKey, settings.provider.apiKey)
        XCTAssertEqual(loaded.provider.supportsOnlineSearch, settings.provider.supportsOnlineSearch)
        XCTAssertEqual(loaded.provider.timeoutSeconds, TrendAIProviderSettings.defaultGenerationTimeoutSeconds)
        XCTAssertEqual(loaded.defaultPrivacyMode, settings.defaultPrivacyMode)
        XCTAssertEqual(loaded.dailyAutoAnalysisEnabled, settings.dailyAutoAnalysisEnabled)
        XCTAssertEqual(loaded.lastAutoAnalysisDay, settings.lastAutoAnalysisDay)
    }

    func testSettingsStoreUpgradesLegacyShortProviderTimeout() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("trend-settings.json")
        try """
        {
          "dailyAutoAnalysisEnabled": false,
          "defaultPrivacyMode": "完整明细",
          "lastAutoAnalysisDay": null,
          "provider": {
            "apiKey": "sk-test-value",
            "baseURL": "https://open.bigmodel.cn/api/coding/paas/v4",
            "model": "glm-5.2",
            "providerName": "智谱",
            "supportsOnlineSearch": true,
            "timeoutSeconds": 60
          }
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try TrendAnalysisSettingsStore().load(from: url)

        XCTAssertEqual(loaded.provider.timeoutSeconds, TrendAIProviderSettings.defaultGenerationTimeoutSeconds)
    }

    func testReportStoreKeepsLatestSuccessfulReport() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("trend-report.json")
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-22 10:00:00",
            externalSignalStatus: .available
        )

        try TrendAnalysisReportStore().save(report, to: url)
        let loaded = try TrendAnalysisReportStore().load(from: url)

        XCTAssertEqual(loaded?.generatedAt, "2026-06-22 10:00:00")
        XCTAssertEqual(loaded?.externalSignalStatus, .available)
    }

    func testSameDayAutoAnalysisUsesStoredLocalDay() {
        let settings = TrendAnalysisSettings(
            provider: .empty,
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: true,
            lastAutoAnalysisDay: "2026-06-22"
        )

        XCTAssertTrue(settings.hasAutoAnalyzed(on: "2026-06-22"))
        XCTAssertFalse(settings.hasAutoAnalyzed(on: "2026-06-23"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension TrendAnalysisReport {
    static func fixture(
        generatedAt: String,
        externalSignalStatus: TrendExternalSignalStatus
    ) -> TrendAnalysisReport {
        TrendAnalysisReport(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            generatedAt: generatedAt,
            dataAsOf: "2026-06-22 09:58:00",
            privacyMode: .sanitized,
            externalSignalStatus: externalSignalStatus,
            portfolio: TrendPortfolioSummary(
                headline: "组合偏中性",
                riskLevel: .medium,
                summary: "仓位集中度可控，外部信号需要继续观察。"
            ),
            horizons: [
                TrendHorizonView(
                    horizon: .short,
                    direction: .neutral,
                    confidence: TrendConfidence(score: 62, label: "中"),
                    rationale: "短期缺少明确突破信号。",
                    counterSignals: ["成交量放大后可能改变短期判断"]
                )
            ],
            sectors: [],
            keyAssets: [],
            actions: [],
            evidence: [],
            warnings: [],
            disclaimer: "非投资建议，仅供个人研究参考。"
        )
    }

    func replacingActions(_ actions: [TrendActionCandidate]) -> TrendAnalysisReport {
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
