import XCTest
@testable import QiemanDashboard

final class TrendAgentRunnerTests: XCTestCase {
    func testProcessClientCapturesStdoutAndExitCode() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            echo '{"ok":true}'
            """
        )

        let result = try await TrendAgentProcessClient().run(
            executableURL: executable,
            arguments: [],
            currentDirectoryURL: executable.deletingLastPathComponent(),
            standardInput: nil,
            timeoutSeconds: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains(#""ok":true"#))
    }

    func testProcessClientReportsNonZeroExit() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            echo 'bad' >&2
            exit 7
            """
        )

        let result = try await TrendAgentProcessClient().run(
            executableURL: executable,
            arguments: [],
            currentDirectoryURL: executable.deletingLastPathComponent(),
            standardInput: nil,
            timeoutSeconds: 5
        )

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertTrue(result.stderr.contains("bad"))
    }

    func testExternalRunnerReadsOutputFileFromCommand() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            output="$2"
            cat > "$output" <<'JSON'
            {"generatedAt":"2026-06-24 10:00:00","dataAsOf":"2026-06-24 10:00:00","privacyMode":"脱敏摘要","externalSignalStatus":"partial","portfolio":{"headline":"测试","riskLevel":"medium","summary":"测试摘要"},"horizons":[{"horizon":"short","direction":"neutral","confidence":{"score":60,"label":"中"},"rationale":"测试判断","counterSignals":["测试反证"]}],"sectors":[],"keyAssets":[],"actions":[],"evidence":[],"warnings":[],"disclaimer":"非投资建议，仅供个人研究参考。"}
            JSON
            """
        )
        let packet = try makePacket()
        let settings = TrendAgentSettings(
            kind: .custom,
            commandPath: executable.path,
            model: "",
            profile: "",
            timeoutSeconds: 5,
            customCommandTemplate: "{{command}} {{promptFile}} {{outputFile}}"
        )

        let result = try await TrendAgentRunner(processClient: TrendAgentProcessClient()).generateReport(
            packet: packet,
            settings: settings,
            candidates: []
        )

        XCTAssertTrue(result.reportJSON.contains(#""headline":"测试""#))
        XCTAssertEqual(result.commandPath, executable.path)
    }

    func testClaudeRunnerReadsPromptFromStandardInputAndExtractsResultJSON() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            stdin="$(cat)"
            if [ "$stdin" != "prompt" ]; then
              exit 0
            fi
            cat <<'JSON'
            {"type":"result","subtype":"success","is_error":false,"result":"{\\"generatedAt\\":\\"2026-06-24 10:00:00\\",\\"dataAsOf\\":\\"2026-06-24 10:00:00\\",\\"privacyMode\\":\\"脱敏摘要\\",\\"externalSignalStatus\\":\\"partial\\",\\"portfolio\\":{\\"headline\\":\\"Claude JSON\\",\\"riskLevel\\":\\"medium\\",\\"summary\\":\\"测试摘要\\"},\\"horizons\\":[{\\"horizon\\":\\"short\\",\\"direction\\":\\"neutral\\",\\"confidence\\":{\\"score\\":60,\\"label\\":\\"中\\"},\\"rationale\\":\\"测试判断\\",\\"counterSignals\\":[\\"测试反证\\"]}],\\"sectors\\":[],\\"keyAssets\\":[],\\"actions\\":[],\\"evidence\\":[],\\"warnings\\":[],\\"disclaimer\\":\\"非投资建议，仅供个人研究参考。\\"}","session_id":"test"}
            JSON
            """
        )
        let packet = try makePacket()
        let settings = TrendAgentSettings(
            kind: .claudeCLI,
            commandPath: "",
            model: "",
            profile: "",
            timeoutSeconds: 5,
            customCommandTemplate: ""
        )

        let result = try await TrendAgentRunner(processClient: TrendAgentProcessClient()).generateReport(
            packet: packet,
            settings: settings,
            candidates: [makeClaudeCandidate(path: executable.path)]
        )
        let report = try JSONDecoder().decode(TrendAnalysisReport.self, from: Data(result.reportJSON.utf8))

        XCTAssertEqual(report.portfolio.headline, "Claude JSON")
    }

    func testClaudeRunnerSurfacesWrapperAPIError() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            cat >/dev/null
            cat <<'JSON'
            {"type":"result","subtype":"success","is_error":true,"api_error_status":529,"result":"API Error: 529 overloaded","session_id":"test"}
            JSON
            """
        )
        let packet = try makePacket()
        let settings = TrendAgentSettings(
            kind: .claudeCLI,
            commandPath: "",
            model: "",
            profile: "",
            timeoutSeconds: 5,
            customCommandTemplate: ""
        )

        do {
            _ = try await TrendAgentRunner(processClient: TrendAgentProcessClient()).generateReport(
                packet: packet,
                settings: settings,
                candidates: [makeClaudeCandidate(path: executable.path)]
            )
            XCTFail("Expected Claude wrapper error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Claude CLI 服务繁忙（529）"))
            XCTAssertTrue(error.localizedDescription.contains("切换到 Codex CLI"))
        }
    }

    func testClaudeRunnerSummarizesNonZeroJSONOverloadError() async throws {
        let executable = try makeExecutable(
            body: """
            #!/usr/bin/env bash
            cat >/dev/null
            cat <<'JSON'
            {"type":"result","subtype":"success","is_error":true,"api_error_status":529,"result":"API Error: 529 [1305] 该模型当前访问量过大，请您稍后再试","session_id":"test"}
            JSON
            exit 1
            """
        )
        let packet = try makePacket()
        let settings = TrendAgentSettings(
            kind: .claudeCLI,
            commandPath: "",
            model: "",
            profile: "",
            timeoutSeconds: 5,
            customCommandTemplate: ""
        )

        do {
            _ = try await TrendAgentRunner(processClient: TrendAgentProcessClient()).generateReport(
                packet: packet,
                settings: settings,
                candidates: [makeClaudeCandidate(path: executable.path)]
            )
            XCTFail("Expected Claude overload error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Claude CLI 服务繁忙（529）"))
            XCTAssertTrue(error.localizedDescription.contains("稍后重试"))
            XCTAssertFalse(error.localizedDescription.contains(#""type":"result""#))
        }
    }

    func testAutomaticRunnerFailsWhenNoCandidatesAreRunnable() async {
        let packet = try! makePacket()
        let settings = TrendAgentSettings.default

        do {
            _ = try await TrendAgentRunner(processClient: TrendAgentProcessClient()).generateReport(
                packet: packet,
                settings: settings,
                candidates: []
            )
            XCTFail("Expected no runnable agent error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("未找到可运行"))
        }
    }

    private func makeExecutable(body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-agent")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makePacket() throws -> TrendRunPacket {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-packet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("output", isDirectory: true),
            withIntermediateDirectories: true
        )
        let promptURL = directory.appendingPathComponent("prompt.md")
        let contextURL = directory.appendingPathComponent("input.json")
        let schemaURL = directory.appendingPathComponent("schema.json")
        let outputURL = directory.appendingPathComponent("output/trend-report.json")
        let logURL = directory.appendingPathComponent("output/agent-log.txt")
        try "prompt".write(to: promptURL, atomically: true, encoding: .utf8)
        try "{}".write(to: contextURL, atomically: true, encoding: .utf8)
        try "{}".write(to: schemaURL, atomically: true, encoding: .utf8)
        return TrendRunPacket(
            runDirectory: directory,
            promptURL: promptURL,
            contextURL: contextURL,
            schemaURL: schemaURL,
            outputURL: outputURL,
            logURL: logURL
        )
    }

    private func makeClaudeCandidate(path: String) -> TrendAgentCandidate {
        TrendAgentCandidate(
            id: "claude",
            kind: .claudeCLI,
            displayName: "Claude CLI",
            commandPath: path,
            version: nil,
            isInstalled: true,
            isExecutable: true,
            capabilities: [.nonInteractive, .jsonSchema],
            warning: nil
        )
    }
}
