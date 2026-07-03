import Foundation

struct TradeSignalNotificationState: Codable, Hashable {
    private(set) var sentKeys: Set<String>

    init(sentKeys: Set<String> = []) {
        self.sentKeys = sentKeys
    }

    func hasSent(_ key: String) -> Bool {
        sentKeys.contains(key)
    }

    mutating func markSent(_ key: String) {
        sentKeys.insert(key)
    }
}

struct TradeSignalNotificationRequest: Hashable {
    let key: String
    let title: String
    let body: String
    let item: TradeSignalItem
}

struct TradeSignalNotificationDecision {
    static func makeRequests(
        summary: TradeSignalSummary,
        settings: TradeSignalSettings,
        state: TradeSignalNotificationState,
        day: String
    ) -> [TradeSignalNotificationRequest] {
        guard settings.enabled, settings.localNotificationsEnabled else { return [] }
        return summary.items.compactMap { item in
            guard shouldNotify(item) else { return nil }
            let key = notificationKey(day: day, item: item)
            guard !state.hasSent(key) else { return nil }
            return TradeSignalNotificationRequest(
                key: key,
                title: "AI 操作观察：\(item.assetName)\(item.status.displayText)",
                body: notificationBody(for: item),
                item: item
            )
        }
    }

    static func notificationKey(day: String, item: TradeSignalItem) -> String {
        [
            day,
            item.assetKey ?? item.assetName,
            item.action.rawValue,
            item.status.rawValue
        ].joined(separator: "|")
    }

    private static func shouldNotify(_ item: TradeSignalItem) -> Bool {
        switch item.status {
        case .new, .approaching, .triggered, .invalidated, .upgraded:
            return true
        case .staleAnalysis:
            return false
        }
    }

    private static func notificationBody(for item: TradeSignalItem) -> String {
        let stale = item.isBasedOnStaleAnalysis ? "基于上次 AI 分析。" : ""
        return "\(item.action.displayText)：\(item.triggerSummary)。\(stale)打开工作台查看完整条件。"
    }
}

struct TradeSignalNotificationStateStore {
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load(from fileURL: URL) throws -> TradeSignalNotificationState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TradeSignalNotificationState()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(TradeSignalNotificationState.self, from: data)
    }

    func save(_ state: TradeSignalNotificationState, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
