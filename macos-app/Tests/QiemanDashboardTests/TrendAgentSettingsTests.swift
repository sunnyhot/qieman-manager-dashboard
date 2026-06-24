import XCTest
@testable import QiemanDashboard

final class TrendAgentSettingsTests: XCTestCase {
    func testDefaultAgentSettingsUseAutomaticSelection() {
        let settings = TrendAgentSettings.default

        XCTAssertEqual(settings.kind, .automatic)
        XCTAssertEqual(settings.commandPath, "")
        XCTAssertEqual(settings.model, "")
        XCTAssertEqual(settings.profile, "")
        XCTAssertEqual(settings.timeoutSeconds, 300)
        XCTAssertEqual(settings.customCommandTemplate, "")
    }

    func testConfiguredAgentRequiresConcreteCommandForCustomKind() {
        var settings = TrendAgentSettings(
            kind: .custom,
            commandPath: "",
            model: "",
            profile: "",
            timeoutSeconds: 300,
            customCommandTemplate: "{{command}} {{promptFile}} {{schemaFile}} {{outputFile}} {{runDir}}"
        )

        XCTAssertFalse(settings.isRunnable(with: []))

        settings.commandPath = "/usr/local/bin/hermes"

        XCTAssertTrue(settings.isRunnable(with: []))
    }

    func testAutomaticAgentUsesFirstRunnableCandidate() {
        let settings = TrendAgentSettings.default
        let candidates = [
            TrendAgentCandidate(
                id: "claude",
                kind: .claudeCLI,
                displayName: "Claude CLI",
                commandPath: "/Users/test/.local/bin/claude",
                version: "1.0.0",
                isInstalled: true,
                isExecutable: true,
                capabilities: [.jsonSchema, .nonInteractive],
                warning: nil
            )
        ]

        XCTAssertTrue(settings.isRunnable(with: candidates))
        XCTAssertEqual(settings.resolvedCandidate(from: candidates)?.kind, .claudeCLI)
    }
}
