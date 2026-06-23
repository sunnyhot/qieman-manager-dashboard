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

    func testZhipuClaudeConfigMapsToOpenAICompatibleEndpoint() throws {
        let home = try temporaryDirectory()
        try "{}".write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: [
                "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
                "ANTHROPIC_MODEL": "glm-5.1",
                "ANTHROPIC_API_KEY": "sk-zhipu-secret"
            ]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "claude-zhipu-openai-compatible" })
        XCTAssertTrue(candidate.canImport)
        XCTAssertEqual(candidate.compatibility, .openAICompatible)
        XCTAssertEqual(candidate.baseURL, "https://open.bigmodel.cn/api/coding/paas/v4")
        XCTAssertEqual(candidate.model, "glm-5.1")
        XCTAssertEqual(candidate.apiKeySource, "ANTHROPIC_API_KEY")
        XCTAssertTrue(candidate.warning?.contains("智谱") == true)
    }

    func testZhipuClaudeSettingsJSONAuthTokenMapsToOpenAICompatibleEndpoint() throws {
        let home = try temporaryDirectory()
        let claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try """
        {
          "env": {
            "ANTHROPIC_BASE_URL": "https://open.bigmodel.cn/api/anthropic",
            "ANTHROPIC_AUTH_TOKEN": "zhipu-auth-secret",
            "ANTHROPIC_MODEL": "GLM-5.2"
          }
        }
        """.write(to: claudeDirectory.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        let detector = LocalAIConfigurationDetector(
            homeDirectory: home,
            environment: [:]
        )

        let candidates = detector.detect()

        let candidate = try XCTUnwrap(candidates.first { $0.id == "claude-zhipu-openai-compatible" })
        XCTAssertTrue(candidate.canImport)
        XCTAssertEqual(candidate.baseURL, "https://open.bigmodel.cn/api/coding/paas/v4")
        XCTAssertEqual(candidate.model, "GLM-5.2")
        XCTAssertEqual(candidate.apiKey, "zhipu-auth-secret")
        XCTAssertEqual(candidate.apiKeySource, "ANTHROPIC_AUTH_TOKEN")
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
