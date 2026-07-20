import Foundation

let localized = [
    "include release notes in update manifest": "升级弹窗现在会显示本次更新内容。",
    "format update release notes for display": "优化升级弹窗展示，只显示本次版本更新内容。",
    "expand titlebar zoom hit area": "扩大顶部标题栏双击放大的响应区域。",
]
let hidden: Set<String> = ["align checked-in update notes", "更新 agent 项目指南"]
let prefix = try! NSRegularExpression(
    pattern: #"^(feat|fix|chore|docs|style|refactor|perf|test)(\([^)]+\))?:\s*"#,
    options: [.caseInsensitive]
)
var items: [String] = []

for raw in ProcessInfo.processInfo.environment["RAW_COMMITS", default: ""].components(separatedBy: .newlines) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    let cleaned = prefix.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let key = cleaned.lowercased()
    guard !hidden.contains(key) else { continue }
    let text = localized[key] ?? cleaned
    if !text.isEmpty, !items.contains(text) { items.append(text) }
}

print(items.joined(separator: "\n"))
