import Foundation

enum AppUpdateReleaseNotesFormatter {
    static func items(from rawNotes: String) -> [String] {
        rawNotes
            .components(separatedBy: .newlines)
            .compactMap(cleanedItem)
    }

    private static func cleanedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("---") else { return nil }
        guard !trimmed.contains("自动构建 by GitHub Actions") else { return nil }

        let withoutBullet = trimmed
            .replacingOccurrences(
                of: #"^[-*•]\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let withoutCommitPrefix = withoutBullet
            .replacingOccurrences(
                of: #"^(feat|fix|chore|docs|style|refactor|perf|test)(\([^)]+\))?:\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !withoutCommitPrefix.isEmpty else { return nil }
        return localizedItem(withoutCommitPrefix)
    }

    private static func localizedItem(_ item: String) -> String {
        switch item.lowercased() {
        case "include release notes in update manifest":
            return "升级弹窗现在只展示本次更新内容。"
        case "expand titlebar zoom hit area":
            return "扩大顶部标题栏双击放大的响应区域。"
        default:
            return item
        }
    }
}
