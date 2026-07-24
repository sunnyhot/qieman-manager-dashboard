import XCTest
@testable import QiemanDashboard

// 阶段四：AppModel 趋势分析新流程（内嵌 Agent）的单元测试。
// 通过注入 FakeTrendResearchAgent 与假能力探测器驱动，不访问真实模型。
@MainActor
final class TrendAnalysisAppModelTests: XCTestCase {

    func testSuccessfulGenerationStoresReport() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings()
        installSupportingProbe(model)
        let report = TrendAnalysisReport.fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .partial)
        model.trendResearchAgent = FakeTrendResearchAgent(result: .success(report))

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .succeeded)
        XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-22 12:00:00")
        XCTAssertEqual(model.lastTrendGeneratedAt, "2026-06-22 12:00:00")
    }

    func testFailedGenerationKeepsLastReport() async {
        let model = AppModel()
        let previous = TrendAnalysisReport.fixture(generatedAt: "2026-06-21 12:00:00", externalSignalStatus: .partial)
        model.trendReport = previous
        model.trendSettings = makeProviderSettings()
        installSupportingProbe(model)
        model.trendResearchAgent = FakeTrendResearchAgent(result: .failure(TrendResearchAgentError.turnLimitExceeded))

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .failed)
        // 失败不覆盖旧报告。
        XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-21 12:00:00")
        XCTAssertFalse(model.lastTrendError.isEmpty)
    }

    func testCancelledGenerationKeepsLastReport() async {
        let model = AppModel()
        let previous = TrendAnalysisReport.fixture(generatedAt: "2026-06-21 12:00:00", externalSignalStatus: .partial)
        model.trendReport = previous
        model.trendSettings = makeProviderSettings()
        installSupportingProbe(model)
        model.trendResearchAgent = FakeTrendResearchAgent(result: .failure(CancellationError()))

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .failed)
        XCTAssertEqual(model.trendReport?.generatedAt, "2026-06-21 12:00:00")
    }

    func testUnsupportedProviderIsGatedAndAgentNotRun() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings()
        let agent = FakeTrendResearchAgent(result: .success(TrendAnalysisReport.fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .partial)))
        model.trendResearchAgent = agent
        // 注入返回"不支持工具调用"的假探测器；fail-closed 下 Agent 不得运行。
        let fingerprint = model.trendSettings.provider.fingerprint
        model.trendCapabilityProbe = { _ in
            TrendProviderCapabilities(
                supportsToolCalls: false,
                supportsForcedToolChoice: false,
                providerFingerprint: fingerprint,
                checkedAt: "2026-06-22 12:00:00",
                detail: "仅返回普通文本"
            )
        }

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        XCTAssertEqual(model.trendGenerationState, .failed)
        XCTAssertEqual(agent.runCount, 0)
        XCTAssertTrue(model.lastTrendError.contains("不支持工具调用"))
    }

    func testDailyAutoAnalysisRunsOncePerScheduledSlot() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings(dailyAutoAnalysisEnabled: true)
        model.trendSettings.dailyAutoAnalysisTimes = ["09:30", "14:30"]
        installSupportingProbe(model)
        let agent = FakeTrendResearchAgent(result: .success(TrendAnalysisReport.fixture(generatedAt: "2026-06-22 09:30:00", externalSignalStatus: .partial)))
        model.trendResearchAgent = agent

        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 09:30:00")
        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 10:00:00")
        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 15:00:00")
        await model.runDailyTrendAnalysisIfNeeded(createdAt: "2026-06-22 16:00:00")

        XCTAssertEqual(agent.runCount, 2)
        XCTAssertEqual(model.trendSettings.lastAutoAnalysisDay, "2026-06-22")
        XCTAssertEqual(model.trendSettings.lastAutoAnalysisSlotKey, "2026-06-22 14:30")
    }

    func testProgressLogsReflectAgentEvents() async {
        let model = AppModel()
        model.trendSettings = makeProviderSettings()
        installSupportingProbe(model)
        let report = TrendAnalysisReport.fixture(generatedAt: "2026-06-22 12:00:00", externalSignalStatus: .partial)
        model.trendResearchAgent = FakeTrendResearchAgent(result: .success(report))

        await model.generateTrendAnalysis(userInitiated: true, createdAt: "2026-06-22 12:00:00")

        let messages = model.trendProgressLogs.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("内嵌趋势 Agent") })
        XCTAssertTrue(messages.contains { $0.contains("趋势分析完成") })
    }

    // MARK: - 辅助

    private func makeProviderSettings(dailyAutoAnalysisEnabled: Bool = false) -> TrendAnalysisSettings {
        TrendAnalysisSettings(
            provider: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://api.example.com/v1",
                model: "glm-5.2",
                apiKey: "sk-test",
                timeoutSeconds: 300
            ),
            defaultPrivacyMode: .sanitized,
            dailyAutoAnalysisEnabled: dailyAutoAnalysisEnabled
        )
    }

    /// 注入返回"支持工具调用"的假探测器，避免测试联网；指纹与当前 Provider 一致以跳过重复探测。
    private func installSupportingProbe(_ model: AppModel) {
        let fingerprint = model.trendSettings.provider.fingerprint
        model.trendCapabilityProbe = { _ in
            TrendProviderCapabilities(
                supportsToolCalls: true,
                supportsForcedToolChoice: true,
                providerFingerprint: fingerprint,
                checkedAt: "2026-06-22 12:00:00",
                detail: "支持工具调用"
            )
        }
    }
}

/// 记录调用次数、按预设结果返回的假 Agent。
private final class FakeTrendResearchAgent: TrendResearchAgentProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var runCount = 0
    let result: Result<TrendAnalysisReport, Error>

    init(result: Result<TrendAnalysisReport, Error>) {
        self.result = result
    }

    func run(
        snapshot: TrendResearchSnapshot,
        settings: TrendAIProviderSettings,
        webSearchSettings: TavilySearchSettings = .empty,
        eventHandler: @escaping @Sendable (TrendResearchAgentEvent) -> Void
    ) async throws -> TrendAnalysisReport {
        lock.lock()
        runCount += 1
        lock.unlock()
        eventHandler(.started(runID: snapshot.runID))
        eventHandler(.turnStarted(1))
        eventHandler(.completed(duration: 0.1))
        switch result {
        case .success(let report):
            return report
        case .failure(let error):
            throw error
        }
    }
}
