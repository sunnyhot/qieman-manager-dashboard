import XCTest
@testable import QiemanDashboard

final class LocalAIConfigurationDetectorTests: XCTestCase {
    func testDetectsOpenAICompatibleEnvironmentCandidate() throws {
        let detector = LocalAIConfigurationDetector(
            homeDirectory: try temporaryDirectory(),
            environment: [
                "OPENAI_API_KEY": "sk-live-secret",
                "OPENAI_BASE_URL": "https://api.openai.com/v1",
                "OPENAI_MODEL": "gpt-4.1"
            ]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "env-openai" })
        XCTAssertTrue(candidate.canImport)
        XCTAssertEqual(candidate.providerName, "OpenAI-compatible environment")
        XCTAssertEqual(candidate.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(candidate.model, "gpt-4.1")
        XCTAssertEqual(candidate.maskedAPIKey, "sk-...cret")
        XCTAssertFalse(candidate.sourceDescription.contains("sk-live-secret"))
    }

    func testDetectsCodexConfigWithoutExposingEnvSecret() throws {
        let home = try temporaryDirectory()
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try """
        model = "openai/gpt-4.1"
        [model_providers.openrouter]
        base_url = "https://openrouter.ai/api/v1"
        env_key = "OPENROUTER_API_KEY"
        """.write(to: codexDirectory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: ["OPENROUTER_API_KEY": "sk-or-secret"]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "codex-openrouter" })
        XCTAssertTrue(candidate.canImport)
        XCTAssertEqual(candidate.baseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(candidate.apiKeySource, "OPENROUTER_API_KEY")
        XCTAssertEqual(candidate.maskedAPIKey, "sk-...cret")
    }

    func testCodexConfigWithoutAvailableEnvSecretIsNotImportable() throws {
        let home = try temporaryDirectory()
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try """
        model = "openai/gpt-4.1"
        [model_providers.openrouter]
        base_url = "https://openrouter.ai/api/v1"
        env_key = "OPENROUTER_API_KEY"
        """.write(to: codexDirectory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: [:]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "codex-openrouter" })
        XCTAssertFalse(candidate.canImport)
        XCTAssertEqual(candidate.compatibility, .incomplete)
        XCTAssertTrue(candidate.warning?.contains("OPENROUTER_API_KEY") == true)
    }

    func testClaudeConfigIsDetectedButNotImportableForOpenAICompatibleClient() throws {
        let home = try temporaryDirectory()
        try "{}".write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: ["ANTHROPIC_API_KEY": "sk-ant-secret"]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "claude-direct" })
        XCTAssertFalse(candidate.canImport)
        XCTAssertEqual(candidate.compatibility, .needsCompatibleEndpoint)
        XCTAssertEqual(candidate.maskedAPIKey, "sk-...cret")
        XCTAssertTrue(candidate.warning?.contains("OpenAI-compatible") == true)
    }

    func testDetectorReturnsStableOrderByConfidence() throws {
        let detector = LocalAIConfigurationDetector(
            homeDirectory: try temporaryDirectory(),
            environment: [
                "ANTHROPIC_API_KEY": "sk-ant-secret",
                "OPENAI_API_KEY": "sk-openai-secret",
                "OPENAI_BASE_URL": "https://api.openai.com/v1",
                "OPENAI_MODEL": "gpt-4.1"
            ]
        )

        let candidates = detector.detect()

        XCTAssertEqual(candidates.first?.id, "env-openai")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-ai-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
