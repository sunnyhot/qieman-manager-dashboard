import XCTest
@testable import QiemanDashboard

final class TrendAgentDetectorTests: XCTestCase {
    func testDetectsExecutableClaudeAndCodexFromSearchPaths() throws {
        let directory = try temporaryDirectory()
        let claude = try makeExecutable(named: "claude", in: directory)
        let codex = try makeExecutable(named: "codex", in: directory)

        let candidates = TrendAgentDetector(
            searchPaths: [directory.path],
            fileManager: .default
        ).detect()

        XCTAssertTrue(candidates.contains { $0.kind == .claudeCLI && $0.commandPath == claude.path })
        XCTAssertTrue(candidates.contains { $0.kind == .codexCLI && $0.commandPath == codex.path })
    }

    func testMissingAgentReturnsInstalledFalseCandidate() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-agent-\(UUID().uuidString)", isDirectory: true)

        let candidates = TrendAgentDetector(
            searchPaths: [directory.path],
            fileManager: .default
        ).detect()

        let claude = candidates.first { $0.kind == .claudeCLI }
        XCTAssertEqual(claude?.isInstalled, false)
        XCTAssertEqual(claude?.isExecutable, false)
    }

    func testDetectionOrderPrefersClaudeThenCodexThenExternalAgents() throws {
        let directory = try temporaryDirectory()
        _ = try makeExecutable(named: "hermes", in: directory)
        _ = try makeExecutable(named: "codex", in: directory)
        _ = try makeExecutable(named: "claude", in: directory)

        let kinds = TrendAgentDetector(
            searchPaths: [directory.path],
            fileManager: .default
        ).detect().map(\.kind)

        XCTAssertLessThan(kinds.firstIndex(of: .claudeCLI)!, kinds.firstIndex(of: .codexCLI)!)
        XCTAssertLessThan(kinds.firstIndex(of: .codexCLI)!, kinds.firstIndex(of: .hermes)!)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-agent-detector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "#!/usr/bin/env bash\necho \(name)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
