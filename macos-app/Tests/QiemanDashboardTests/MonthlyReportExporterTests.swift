import XCTest
@testable import QiemanDashboard

final class MonthlyReportExporterTests: XCTestCase {
    func testDefaultArchiveURLUsesMonthFileNameInsideReportsDirectory() throws {
        let directory = try temporaryDirectory()
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()

        let url = exporter.defaultArchiveURL(for: report, in: directory)

        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Reports")
        XCTAssertEqual(url.lastPathComponent, "2026-06-portfolio-report.md")
    }

    func testArchiveWritesMarkdownAndMetadata() throws {
        let directory = try temporaryDirectory()
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()

        let metadata = try exporter.archive(report: report, in: directory, exportedAt: "2026-06-12 10:30:00", overwriteConfirmed: false)
        let content = try String(contentsOf: URL(fileURLWithPath: metadata.filePath), encoding: .utf8)

        XCTAssertEqual(content, report.markdown)
        XCTAssertEqual(metadata.monthText, "2026-06")
        XCTAssertEqual(metadata.exportedAt, "2026-06-12 10:30:00")
    }

    func testArchiveRequiresConfirmationBeforeOverwritingSameMonth() throws {
        let directory = try temporaryDirectory()
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()
        _ = try exporter.archive(report: report, in: directory, exportedAt: "2026-06-12 10:30:00", overwriteConfirmed: false)

        XCTAssertThrowsError(
            try exporter.archive(report: report, in: directory, exportedAt: "2026-06-12 10:31:00", overwriteConfirmed: false)
        ) { error in
            guard case MonthlyReportExportError.archiveAlreadyExists(let url) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url.lastPathComponent, "2026-06-portfolio-report.md")
        }
    }

    func testArchiveOverwritesWhenConfirmed() throws {
        let directory = try temporaryDirectory()
        let first = sampleReport(month: "2026-06", markdown: "# First")
        let second = sampleReport(month: "2026-06", markdown: "# Second")
        let exporter = MonthlyReportExporter()
        _ = try exporter.archive(report: first, in: directory, exportedAt: "2026-06-12 10:30:00", overwriteConfirmed: false)

        let metadata = try exporter.archive(report: second, in: directory, exportedAt: "2026-06-12 10:31:00", overwriteConfirmed: true)
        let content = try String(contentsOf: URL(fileURLWithPath: metadata.filePath), encoding: .utf8)

        XCTAssertEqual(content, "# Second")
    }

    func testSaveAsWritesToChosenURL() throws {
        let directory = try temporaryDirectory()
        let targetURL = directory.appendingPathComponent("custom-report.md")
        let report = sampleReport(month: "2026-06")
        let exporter = MonthlyReportExporter()

        let metadata = try exporter.saveAs(report: report, to: targetURL, exportedAt: "2026-06-12 10:30:00")

        XCTAssertEqual(metadata.filePath, targetURL.path)
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), report.markdown)
    }

    func testMarkdownRemainsAvailableAfterWriteFailure() throws {
        let directory = try temporaryDirectory()
        let targetURL = directory.appendingPathComponent("missing").appendingPathComponent("report.md")
        let report = sampleReport(month: "2026-06", markdown: "# Still Available")
        let exporter = MonthlyReportExporter()

        XCTAssertThrowsError(try exporter.saveAs(report: report, to: targetURL, exportedAt: "2026-06-12 10:30:00"))
        XCTAssertEqual(report.markdown, "# Still Available")
    }

    private func sampleReport(month: String, markdown: String = "# Report") -> MonthlyReportSummary {
        MonthlyReportSummary(
            title: "且慢主理人看板月报 \(month)",
            monthText: month,
            generatedAt: "\(month)-12 10:30:00",
            markdown: markdown
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("monthly-report-exporter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
