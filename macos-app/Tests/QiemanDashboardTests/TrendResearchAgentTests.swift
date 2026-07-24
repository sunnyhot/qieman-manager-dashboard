import XCTest
@testable import QiemanDashboard

// 阶段三：TrendResearchAgent 运行循环单元测试（脚本化 Fake Client 驱动）。
final class TrendResearchAgentTests: XCTestCase {

    func testOverviewThenSubmitSucceeds() async throws {
        let snapshot = makeEmptySnapshot()
        let report = TrendAnalysisReport.fixture(generatedAt: "1999-01-01 00:00:00", externalSignalStatus: .partial)
        let reportJSON = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))

        let client = ScriptedTrendAgentClient([
            .success(toolCallResponse([
                AgentToolCall(id: "c1", function: AgentToolFunctionCall(name: "get_portfolio_overview", arguments: "{}"))
            ])),
            .success(toolCallResponse([
                AgentToolCall(id: "c2", function: AgentToolFunctionCall(name: "submit_trend_report", arguments: "{\"report\":\(reportJSON)}"))
            ]))
        ])
        let agent = TrendResearchAgent(client: client)

        let result = try await agent.run(snapshot: snapshot, settings: testSettings()) { _ in }
        XCTAssertEqual(result.privacyMode, .sanitized)
        XCTAssertNotEqual(result.generatedAt, "1999-01-01 00:00:00")
        XCTAssertEqual(result.dataAsOf, "2026-07-24 09:58:00")
    }

    func testPlainTextFirstThenRecoversToTools() async throws {
        let snapshot = makeEmptySnapshot()
        let report = TrendAnalysisReport.fixture(generatedAt: "2026-07-24 10:00:00", externalSignalStatus: .partial)
        let reportJSON = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))

        let client = ScriptedTrendAgentClient([
            .success(plainTextResponse("我直接给你结论：市场平稳。")),
            .success(toolCallResponse([
                AgentToolCall(id: "c0", function: AgentToolFunctionCall(name: "get_portfolio_overview", arguments: "{}"))
            ])),
            .success(toolCallResponse([
                AgentToolCall(id: "c1", function: AgentToolFunctionCall(name: "submit_trend_report", arguments: "{\"report\":\(reportJSON)}"))
            ]))
        ])
        let agent = TrendResearchAgent(client: client)

        let result = try await agent.run(snapshot: snapshot, settings: testSettings()) { _ in }
        XCTAssertEqual(result.privacyMode, .sanitized)
    }

    func testConsecutivePlainTextFails() async throws {
        let snapshot = makeEmptySnapshot()
        let client = ScriptedTrendAgentClient([
            .success(plainTextResponse("一")),
            .success(plainTextResponse("二")),
            .success(plainTextResponse("三"))
        ])
        let agent = TrendResearchAgent(client: client)

        do {
            _ = try await agent.run(snapshot: snapshot, settings: testSettings()) { _ in }
            XCTFail("Expected missingToolCalls")
        } catch TrendResearchAgentError.missingToolCalls {
            // expected
        }
    }

    func testLengthTruncationDoesNotExecuteIncompleteTool() async throws {
        let snapshot = makeEmptySnapshot()
        let report = TrendAnalysisReport.fixture(generatedAt: "2026-07-24 10:00:00", externalSignalStatus: .partial)
        let reportJSON = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))

        // 第一轮：finish_reason=length 且带一个参数残缺的工具调用，不得被执行。
        let truncated = AgentCompletionResult(
            assistantMessage: AgentChatMessage(role: .assistant, content: nil, toolCalls: [
                AgentToolCall(id: "bad", function: AgentToolFunctionCall(name: "get_portfolio_assets", arguments: "{broken"))
            ]),
            toolCalls: [],
            stopReason: .length,
            finishReason: "length"
        )
        let client = ScriptedTrendAgentClient([
            .success(truncated),
            .success(toolCallResponse([
                AgentToolCall(id: "c0", function: AgentToolFunctionCall(name: "get_portfolio_overview", arguments: "{}"))
            ])),
            .success(toolCallResponse([
                AgentToolCall(id: "c1", function: AgentToolFunctionCall(name: "submit_trend_report", arguments: "{\"report\":\(reportJSON)}"))
            ]))
        ])
        let agent = TrendResearchAgent(client: client)

        let result = try await agent.run(snapshot: snapshot, settings: testSettings()) { _ in }
        XCTAssertEqual(result.privacyMode, .sanitized)
    }

    func testThirdInvalidSubmissionTerminates() async throws {
        let snapshot = makeEmptySnapshot()
        // available 在第一版被 Validator 拒绝，连续提交都会失败。
        let report = TrendAnalysisReport.fixture(generatedAt: "2026-07-24 10:00:00", externalSignalStatus: .available)
        let reportJSON = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))
        let submitCall = AgentToolCall(id: "s", function: AgentToolFunctionCall(name: "submit_trend_report", arguments: "{\"report\":\(reportJSON)}"))

        let overviewCall = AgentToolCall(id: "o", function: AgentToolFunctionCall(name: "get_portfolio_overview", arguments: "{}"))
        let client = ScriptedTrendAgentClient([
            .success(toolCallResponse([overviewCall])),
            .success(toolCallResponse([submitCall])),
            .success(toolCallResponse([submitCall])),
            .success(toolCallResponse([submitCall]))
        ])
        let agent = TrendResearchAgent(client: client)

        do {
            _ = try await agent.run(snapshot: snapshot, settings: testSettings()) { _ in }
            XCTFail("Expected invalidSubmissionLimitExceeded")
        } catch TrendResearchAgentError.invalidSubmissionLimitExceeded {
            // expected
        }
    }

    func testSubmitBeforeOverviewIsRejected() async throws {
        let snapshot = makeEmptySnapshot()
        let report = TrendAnalysisReport.fixture(generatedAt: "2026-07-24 10:00:00", externalSignalStatus: .partial)
        let reportJSON = try XCTUnwrap(String(data: JSONEncoder().encode(report), encoding: .utf8))
        let submitCall = AgentToolCall(id: "s", function: AgentToolFunctionCall(name: "submit_trend_report", arguments: "{\"report\":\(reportJSON)}"))
        let overviewCall = AgentToolCall(id: "o", function: AgentToolFunctionCall(name: "get_portfolio_overview", arguments: "{}"))

        // 第 1 轮直接 submit（未先 overview）→ 运行时拒绝；第 2 轮 overview；第 3 轮 submit 成功。
        // 若门控失效，首轮 submit 会直接成功，只消耗 1 条响应。
        let client = ScriptedTrendAgentClient([
            .success(toolCallResponse([submitCall])),
            .success(toolCallResponse([overviewCall])),
            .success(toolCallResponse([submitCall]))
        ])
        let agent = TrendResearchAgent(client: client)

        let result = try await agent.run(snapshot: snapshot, settings: testSettings()) { _ in }
        XCTAssertEqual(result.privacyMode, .sanitized)
        XCTAssertEqual(client.responsesConsumed, 3)
    }

    func testTurnLimitExceeded() async throws {
        let snapshot = makeEmptySnapshot()
        // 每轮只调用只读工具、从不 submit，2 轮后触发 turnLimitExceeded。
        var policy = TrendResearchRunPolicy()
        policy.maxTurns = 2
        let overview = AgentToolCall(id: "o", function: AgentToolFunctionCall(name: "get_portfolio_overview", arguments: "{}"))
        let client = ScriptedTrendAgentClient([
            .success(toolCallResponse([overview])),
            .success(toolCallResponse([overview]))
        ])
        let agent = TrendResearchAgent(client: client, policy: policy)

        do {
            _ = try await agent.run(snapshot: snapshot, settings: testSettings()) { _ in }
            XCTFail("Expected turnLimitExceeded")
        } catch TrendResearchAgentError.turnLimitExceeded {
            // expected
        }
    }

    // MARK: - 辅助

    private func makeEmptySnapshot() -> TrendResearchSnapshot {
        TrendResearchSnapshot(
            runID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            createdAt: "2026-07-24 10:00:00",
            dataAsOf: "2026-07-24 09:58:00",
            privacyMode: .sanitized,
            portfolio: TrendContextPortfolio(
                assetCount: 0, holdingCount: 0, activePlanCount: 0, pendingAssetCount: 0,
                totalMarketValue: nil, totalPendingCashAmount: nil,
                totalEstimatedNextPlanAmount: nil, totalEffectiveHoldingAmount: nil
            ),
            assets: [],
            sectors: [],
            platformSignals: [],
            managerSignals: [],
            marketQuotes: [],
            insightHeadline: "",
            sourceWarnings: []
        )
    }

    private func testSettings() -> TrendAIProviderSettings {
        TrendAIProviderSettings(
            providerName: "Test",
            baseURL: "https://api.example.com/v1",
            model: "glm-5.2",
            apiKey: "sk-test",
            timeoutSeconds: 15
        )
    }

    private func toolCallResponse(_ calls: [AgentToolCall], finishReason: String = "tool_calls") -> AgentCompletionResult {
        let message = AgentChatMessage(role: .assistant, content: nil, toolCalls: calls)
        return AgentCompletionResult(
            assistantMessage: message,
            toolCalls: calls,
            stopReason: AgentStopReason(finishReason: finishReason),
            finishReason: finishReason
        )
    }

    private func plainTextResponse(_ text: String) -> AgentCompletionResult {
        AgentCompletionResult(
            assistantMessage: AgentChatMessage(role: .assistant, content: text),
            toolCalls: [],
            stopReason: .stop,
            finishReason: "stop"
        )
    }
}

/// 按入队顺序逐条返回预设响应的假客户端，用于驱动 Agent 循环测试。
final class ScriptedTrendAgentClient: TrendResearchAgentClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<AgentCompletionResult, Error>]
    private(set) var responsesConsumed = 0

    init(_ responses: [Result<AgentCompletionResult, Error>]) {
        self.responses = responses
    }

    func complete(
        messages: [AgentChatMessage],
        tools: [AgentToolDefinition],
        toolChoice: AgentToolChoice,
        temperature: Double,
        settings: TrendAIProviderSettings,
        timeout: Double?
    ) async throws -> AgentCompletionResult {
        lock.lock()
        responsesConsumed += 1
        let next = responses.isEmpty
            ? Result<AgentCompletionResult, Error>.failure(URLError(.badServerResponse))
            : responses.removeFirst()
        lock.unlock()
        switch next {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
