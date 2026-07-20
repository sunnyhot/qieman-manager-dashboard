import Foundation
import XCTest
@testable import QiemanDashboard

final class QiemanCommandLineTests: XCTestCase {
    func testArgumentParserKeepsRepeatedValuesAndFlags() throws {
        let arguments = try QiemanCommandArguments([
            "valuation",
            "--fund-code", "021550",
            "--fund-code", "001052",
            "--include-content",
        ])

        XCTAssertEqual(arguments.command, "valuation")
        XCTAssertEqual(arguments.strings("fund-code"), ["021550", "001052"])
        XCTAssertTrue(arguments.bool("include-content"))
    }

    func testVersionDeclaresSwiftMacOSRuntime() async throws {
        let command = try QiemanCommandLine(arguments: ["version"])
        let payload = try await command.run()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])

        XCTAssertEqual(object["runtime"] as? String, "swift")
        XCTAssertEqual(object["platform"] as? String, "macos")
    }

    func testHistoricalValuationIsRejectedInsteadOfReturningFakeZero() async throws {
        let command = try QiemanCommandLine(arguments: [
            "valuation",
            "--fund-code", "021550",
            "--at-date", "2026-07-01",
        ])

        do {
            _ = try await command.run()
            XCTFail("应明确拒绝已移除的历史估值参数")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("已移除"))
        }
    }

    func testSignalExtractionKeepsSnakeCaseContract() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qieman-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("posts.json")
        let source: [[String: Any]] = [[
            "title": "计划分批买入宽基指数",
            "publish_date": "2026-07-20",
            "url": "https://example.invalid/post/1",
        ]]
        let data = try JSONSerialization.data(withJSONObject: source)
        try data.write(to: inputURL)

        let command = try QiemanCommandLine(arguments: [
            "signal-extract",
            "--json-path", inputURL.path,
        ])
        let payload = try await command.run()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])

        XCTAssertEqual(object["record_count"] as? Int, 1)
        XCTAssertEqual(object["signal_count"] as? Int, 1)
        let counts = try XCTUnwrap(object["counts"] as? [String: Int])
        XCTAssertEqual(counts["buy"], 1)
    }
}
