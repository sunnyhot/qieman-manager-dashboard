import Foundation

enum FilterMode: String, CaseIterable, Identifiable {
    case managerSubscription = "manager-subscription"
    case preciseParams = "precise-params"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .managerSubscription:
            return "主理人订阅"
        case .preciseParams:
            return "精确参数"
        }
    }
}

enum QueryMode: String, CaseIterable, Identifiable {
    case groupManager = "group-manager"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .groupManager:
            return "公开主理人流"
        }
    }
}

extension QueryMode {
    var producesPostRecords: Bool {
        switch self {
        case .groupManager:
            return true
        }
    }
}

struct QueryFormState {
    // 默认 .preciseParams 保留旧行为（默认 prodCode=LONG_WIN 能直接抓长赢发言）。
    // 主理人订阅模式需用户主动切换并选择主理人，避免冷启动空选刷新报错。
    var filterMode: FilterMode = .preciseParams
    var selectedManagerIds: Set<String> = []
    var mode: QueryMode = .groupManager
    var prodCode: String = "LONG_WIN"
    var managerName: String = ""
    var groupURL: String = ""
    var groupID: String = ""
    var userName: String = "ETF拯救世界"
    var keyword: String = ""
    var since: String = ""
    var until: String = ""
    var pages: String = "5"
    var pageSize: String = "10"
    var autoRefresh: String = ""

    func fetchPayload(persist: Bool) -> [String: Any] {
        var payload: [String: Any] = [
            "mode": mode.rawValue,
            "filter_mode": filterMode.rawValue,
            "selected_manager_ids": selectedManagerIds.sorted(),
            "prod_code": prodCode,
            "manager_name": managerName,
            "group_url": groupURL,
            "group_id": groupID,
            "user_name": userName,
            "keyword": keyword,
            "since": since,
            "until": until,
            "pages": pages,
            "page_size": pageSize,
            "auto_refresh": autoRefresh,
            "persist": persist,
        ]
        payload = payload.filter { key, value in
            if key == "persist" {
                return true
            }
            if let text = value as? String {
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
        return payload
    }
}
