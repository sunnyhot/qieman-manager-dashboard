import Foundation

/// 每次趋势 Agent 运行的本地诊断日志。
///
/// 日志只记录阶段、工具名、耗时和错误，不写入模型或 Tavily API Key。
/// 每次新运行会覆盖上一次，便于在生成失败、App 退出后继续定位原因。
struct TrendAgentRunLogStore {
    func beginRun(
        at fileURL: URL,
        trigger: String,
        model: String,
        startedAt: String
    ) throws {
        let header = """
        # Qieman Trend Agent Run
        started_at: \(startedAt)
        trigger: \(trigger)
        model: \(model)

        """
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(header.utf8).write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func append(_ entry: TrendProgressLog, to fileURL: URL) throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try beginRun(
                at: fileURL,
                trigger: "unknown",
                model: "unknown",
                startedAt: entry.timestamp
            )
        }

        let detail = entry.detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
        let detailText = detail.map { "\n\($0)" } ?? ""
        let line = "[\(entry.timestamp)] [\(entry.level.rawValue)] \(entry.message)\(detailText)\n"

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
    }

    func load(from fileURL: URL) throws -> [TrendProgressLog] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [TrendProgressLog] = []
        var timestamp: String?
        var level: TrendProgressLog.Level?
        var message: String?
        var detailLines: [String] = []

        func flushCurrent() {
            guard let timestamp, let level, let message else { return }
            entries.append(
                TrendProgressLog(
                    timestamp: timestamp,
                    message: message,
                    detail: detailLines.isEmpty ? nil : detailLines.joined(separator: "\n"),
                    level: level
                )
            )
        }

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let parsed = parseEntryLine(line) {
                flushCurrent()
                timestamp = parsed.timestamp
                level = parsed.level
                message = parsed.message
                detailLines = []
            } else if timestamp != nil, line.hasPrefix("    ") {
                detailLines.append(String(line.dropFirst(4)))
            }
        }
        flushCurrent()
        return Array(entries.suffix(50))
    }

    private func parseEntryLine(
        _ line: String
    ) -> (timestamp: String, level: TrendProgressLog.Level, message: String)? {
        guard line.count >= 25, line.first == "[" else { return nil }
        let timestampStart = line.index(after: line.startIndex)
        let timestampEnd = line.index(timestampStart, offsetBy: 19)
        guard timestampEnd < line.endIndex,
              line[timestampEnd...].hasPrefix("] [") else {
            return nil
        }

        let levelStart = line.index(timestampEnd, offsetBy: 3)
        guard let levelEnd = line[levelStart...].firstIndex(of: "]") else { return nil }
        let rawLevel = String(line[levelStart..<levelEnd])
        guard let level = TrendProgressLog.Level(rawValue: rawLevel) else { return nil }

        let messageStart = line.index(after: levelEnd)
        let message = String(line[messageStart...]).trimmingCharacters(in: .whitespaces)
        return (
            timestamp: String(line[timestampStart..<timestampEnd]),
            level: level,
            message: message
        )
    }
}
