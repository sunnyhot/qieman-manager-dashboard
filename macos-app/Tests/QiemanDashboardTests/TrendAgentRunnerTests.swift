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
}
