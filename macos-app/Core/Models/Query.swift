import Foundation

enum QueryMode: String, CaseIterable, Identifiable {
    case followingPosts = "following-posts"
    case groupManager = "group-manager"
    case followingUsers = "following-users"
    case myGroups = "my-groups"
    case spaceItems = "space-items"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followingPosts:
            return "关注动态"
        case .groupManager:
            return "公开主理人流"
        case .followingUsers:
            return "关注用户"
        case .myGroups:
            return "已加入小组"
        case .spaceItems:
            return "个人空间动态"
        }
    }
}

extension QueryMode {
    var producesPostRecords: Bool {
        switch self {
        case .followingPosts, .groupManager, .spaceItems:
            return true
        case .followingUsers, .myGroups:
            return false
        }
    }
}

struct QueryFormState {
    var mode: QueryMode = .followingPosts
    var prodCode: String = "LONG_WIN"
    var managerName: String = ""
    var groupURL: String = ""
    var groupID: String = ""
    var userName: String = "ETF拯救世界"
    var brokerUserID: String = ""
    var spaceUserID: String = ""
    var keyword: String = ""
    var since: String = ""
    var until: String = ""
    var pages: String = "5"
    var pageSize: String = "10"
    var autoRefresh: String = ""

    mutating func apply(defaultForm: DefaultFormPayload) {
        if let mode = QueryMode(rawValue: defaultForm.mode) {
            self.mode = mode
        }
        if !defaultForm.prodCode.isEmpty {
            self.prodCode = defaultForm.prodCode
        }
        if !defaultForm.userName.isEmpty {
            self.userName = defaultForm.userName
        }
        if !defaultForm.pages.isEmpty {
            self.pages = defaultForm.pages
        }
        if !defaultForm.pageSize.isEmpty {
            self.pageSize = defaultForm.pageSize
        }
    }

    func fetchPayload(persist: Bool) -> [String: Any] {
        var payload: [String: Any] = [
            "mode": mode.rawValue,
            "prod_code": prodCode,
            "manager_name": managerName,
            "group_url": groupURL,
            "group_id": groupID,
            "user_name": userName,
            "broker_user_id": brokerUserID,
            "space_user_id": spaceUserID,
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
