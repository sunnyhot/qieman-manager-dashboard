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

    private func makeExecutable(body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-agent")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
