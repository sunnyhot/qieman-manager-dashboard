import Foundation

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
    var mode: QueryMode = .groupManager
    var prodCode: String = "LONG_WIN"
    var managerName: String = ""
    var groupURL: String = ""
    var groupID: String = ""
    var userName: String = "ETF拯救世界"
    var keyword: String = ""
    var since: String = ""
    var until: String = ""
    /// 留空表示持续翻页直到接口没有更多记录。
    var pages: String = ""
    var pageSize: String = "50"
    var autoRefresh: String = ""

    func fetchPayload(persist: Bool) -> [String: Any] {
        var payload: [String: Any] = [
            "mode": mode.rawValue,
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
