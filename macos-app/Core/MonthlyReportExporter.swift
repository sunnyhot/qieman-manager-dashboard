import Foundation

struct MonthlyReportExportMetadata: Codable, Hashable {
    let monthText: String
    let filePath: String
    let exportedAt: String
}

enum MonthlyReportExportError: LocalizedError {
    case archiveAlreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case .archiveAlreadyExists(let url):
            return "月报归档已存在：\(url.path)。确认覆盖后可重新保存。"
        }
    }
}

struct MonthlyReportExporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func reportsDirectory(in dataDirectoryURL: URL) -> URL {
        dataDirectoryURL.appendingPathComponent("Reports", isDirectory: true)
    }

    func defaultArchiveURL(for report: MonthlyReportSummary, in dataDirectoryURL: URL) -> URL {
        reportsDirectory(in: dataDirectoryURL)
            .appendingPathComponent("\(safeMonthText(report.monthText))-portfolio-report.md", isDirectory: false)
    }

    func archive(
        report: MonthlyReportSummary,
        in dataDirectoryURL: URL,
        exportedAt: String,
        overwriteConfirmed: Bool
    ) throws -> MonthlyReportExportMetadata {
        let directory = reportsDirectory(in: dataDirectoryURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let targetURL = defaultArchiveURL(for: report, in: dataDirectoryURL)
        if fileManager.fileExists(atPath: targetURL.path), !overwriteConfirmed {
            throw MonthlyReportExportError.archiveAlreadyExists(targetURL)
        }
        return try write(report: report, to: targetURL, exportedAt: exportedAt)
    }

    func saveAs(report: MonthlyReportSummary, to targetURL: URL, exportedAt: String) throws -> MonthlyReportExportMetadata {
        try write(report: report, to: targetURL, exportedAt: exportedAt)
    }

    private func write(report: MonthlyReportSummary, to targetURL: URL, exportedAt: String) throws -> MonthlyReportExportMetadata {
        try report.markdown.write(to: targetURL, atomically: true, encoding: .utf8)
        return MonthlyReportExportMetadata(
            monthText: report.monthText,
            filePath: targetURL.path,
            exportedAt: exportedAt
        )
    }

    private func safeMonthText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil else {
            return "current-month"
        }
        return trimmed
    }
}

struct MonthlyReportExportMetadataStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> MonthlyReportExportMetadata? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(MonthlyReportExportMetadata.self, from: data)
    }

    func save(_ metadata: MonthlyReportExportMetadata, to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(metadata)
        try data.write(to: fileURL, options: .atomic)
    }
}
