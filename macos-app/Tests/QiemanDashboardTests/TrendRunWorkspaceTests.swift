import XCTest
@testable import QiemanDashboard

final class TrendRunWorkspaceTests: XCTestCase {
    func testPrepareWritesPromptContextSchemaSkillAndOutputDirectory() throws {
        let root = try temporaryDirectory()
        let skillRoot = try makeSkillPack()
        let workspace = TrendRunWorkspace(rootDirectory: root, skillRoot: skillRoot)
        let context = makeTrendContext(privacyMode: .sanitized)
        let prompt = TrendModelPrompt(system: "system instructions", user: "user instructions")

        let packet = try workspace.prepare(context: context, prompt: prompt)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.promptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.contextURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.schemaURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packet.outputURL.deletingLastPathComponent().path))

        let promptText = try String(contentsOf: packet.promptURL)
        XCTAssertTrue(promptText.contains("system instructions"))
        XCTAssertTrue(promptText.contains("user instructions"))
    }

    func testSanitizedContextDoesNotWriteRealAmounts() throws {
        let root = try temporaryDirectory()
        let skillRoot = try makeSkillPack()
        let workspace = TrendRunWorkspace(rootDirectory: root, skillRoot: skillRoot)
        let context = makeTrendContext(privacyMode: .sanitized)

        let packet = try workspace.prepare(context: context, prompt: TrendModelPrompt(system: "s", user: "u"))
        let contextText = try String(contentsOf: packet.contextURL)

        XCTAssertFalse(contextText.contains("123456.78"))
        XCTAssertTrue(contextText.contains("\"privacyMode\""))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-run-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSkillPack() throws -> URL {
        let root = try temporaryDirectory().appendingPathComponent("skill", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("references"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try "Use investment trend analysis.".write(to: root.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "Domain rules".write(to: root.appendingPathComponent("references/domain-rules.md"), atomically: true, encoding: .utf8)
        try "Output contract".write(to: root.appendingPathComponent("references/output-contract.md"), atomically: true, encoding: .utf8)
        try #"{"type":"object"}"#.write(to: root.appendingPathComponent("assets/trend-report.schema.json"), atomically: true, encoding: .utf8)
        try "[]".write(to: root.appendingPathComponent("assets/examples.json"), atomically: true, encoding: .utf8)
        return root
    }

    private func makeTrendContext(privacyMode: TrendPrivacyMode) -> TrendAnalysisContext {
        TrendAnalysisContext(
            createdAt: "2026-06-24 10:00:00",
            privacyMode: privacyMode,
            portfolio: TrendContextPortfolio(
                assetCount: 1,
                holdingCount: 1,
                activePlanCount: 0,
                pendingAssetCount: 0,
                totalMarketValue: privacyMode == .sanitized ? nil : 123_456.78,
                totalPendingCashAmount: nil,
                totalEstimatedNextPlanAmount: nil,
                totalEffectiveHoldingAmount: nil
            ),
            assets: [],
            sectors: [],
            platformSignals: [],
            watchSummary: "暂无",
            insightHeadline: "等待组合快照"
        )
    }
}
