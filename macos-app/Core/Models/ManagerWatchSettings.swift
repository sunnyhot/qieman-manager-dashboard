import Foundation

enum ManagerWatchIntervalOption: Int, CaseIterable, Identifiable, Codable {
    case fiveMinutes = 5
    case tenMinutes = 10
    case thirtyMinutes = 30
    case sixtyMinutes = 60
    case twoHours = 120

    var id: Int { rawValue }

    var label: String {
        switch rawValue {
        case 60:
            return "1 小时"
        case 120:
            return "2 小时"
        default:
            return "\(rawValue) 分钟"
        }
    }
}

struct ManagerWatchSettings: Codable, Hashable {
    var isEnabled: Bool
    var intervalMinutes: Int
    var prodCode: String
    var managerName: String
    var watchPlatform: Bool
    var watchForum: Bool
    var latestSeenPlatformActionID: String?
    var latestSeenForumRecordID: String?
    var lastCheckedAt: String?
    var lastSuccessAt: String?
    var lastErrorMessage: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case intervalMinutes
        case prodCode
        case managerName
        case watchPlatform
        case watchForum
        case latestSeenPlatformActionID
        case latestSeenForumRecordID
        case lastCheckedAt
        case lastSuccessAt
        case lastErrorMessage
    }

    init(
        isEnabled: Bool = false,
        intervalMinutes: Int = 10,
        prodCode: String = "LONG_WIN",
        managerName: String = "ETF拯救世界",
        watchPlatform: Bool = true,
        watchForum: Bool = true,
        latestSeenPlatformActionID: String? = nil,
        latestSeenForumRecordID: String? = nil,
        lastCheckedAt: String? = nil,
        lastSuccessAt: String? = nil,
        lastErrorMessage: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.intervalMinutes = intervalMinutes
        self.prodCode = prodCode
        self.managerName = managerName
        self.watchPlatform = watchPlatform
        self.watchForum = watchForum
        self.latestSeenPlatformActionID = latestSeenPlatformActionID
        self.latestSeenForumRecordID = latestSeenForumRecordID
        self.lastCheckedAt = lastCheckedAt
        self.lastSuccessAt = lastSuccessAt
        self.lastErrorMessage = lastErrorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 10
        self.prodCode = try container.decodeIfPresent(String.self, forKey: .prodCode) ?? "LONG_WIN"
        self.managerName = try container.decodeIfPresent(String.self, forKey: .managerName) ?? "ETF拯救世界"
        self.watchPlatform = try container.decodeIfPresent(Bool.self, forKey: .watchPlatform) ?? true
        self.watchForum = try container.decodeIfPresent(Bool.self, forKey: .watchForum) ?? true
        self.latestSeenPlatformActionID = try container.decodeIfPresent(String.self, forKey: .latestSeenPlatformActionID)
        self.latestSeenForumRecordID = try container.decodeIfPresent(String.self, forKey: .latestSeenForumRecordID)
        self.lastCheckedAt = try container.decodeIfPresent(String.self, forKey: .lastCheckedAt)
        self.lastSuccessAt = try container.decodeIfPresent(String.self, forKey: .lastSuccessAt)
        self.lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
    }

    static let `default` = ManagerWatchSettings(
        isEnabled: false,
        intervalMinutes: ManagerWatchIntervalOption.tenMinutes.rawValue,
        prodCode: "LONG_WIN",
        managerName: "ETF拯救世界",
        watchPlatform: true,
        watchForum: true,
        latestSeenPlatformActionID: nil,
        latestSeenForumRecordID: nil,
        lastCheckedAt: nil,
        lastSuccessAt: nil,
        lastErrorMessage: nil
    )

    var intervalLabel: String {
        ManagerWatchIntervalOption(rawValue: intervalMinutes)?.label ?? "\(intervalMinutes) 分钟"
    }
}

enum NotificationDeepLinkType: String {
    case platformAction = "platform_action"
    case forumRecord = "forum_record"
    case workbenchTrend = "workbench_trend"
}

struct NotificationDeepLinkPayload: Hashable {
    let type: NotificationDeepLinkType
    let targetID: String
    let prodCode: String?
    let managerName: String?

    var userInfo: [AnyHashable: Any] {
        var payload: [AnyHashable: Any] = [
            "deep_link_type": type.rawValue,
            "deep_link_target_id": targetID,
        ]
        if let prodCode, !prodCode.isEmpty {
            payload["deep_link_prod_code"] = prodCode
        }
        if let managerName, !managerName.isEmpty {
            payload["deep_link_manager_name"] = managerName
        }
        return payload
    }

    init(type: NotificationDeepLinkType, targetID: String, prodCode: String? = nil, managerName: String? = nil) {
        self.type = type
        self.targetID = targetID
        self.prodCode = prodCode
        self.managerName = managerName
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let rawType = userInfo["deep_link_type"] as? String,
            let type = NotificationDeepLinkType(rawValue: rawType),
            let targetID = userInfo["deep_link_target_id"] as? String,
            !targetID.isEmpty
        else {
            return nil
        }
        self.type = type
        self.targetID = targetID
        self.prodCode = userInfo["deep_link_prod_code"] as? String
        self.managerName = userInfo["deep_link_manager_name"] as? String
    }
}
