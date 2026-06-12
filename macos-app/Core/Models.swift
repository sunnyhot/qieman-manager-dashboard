import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case portfolio = "我的持仓"
    case platform = "平台调仓"
    case forum = "论坛发言"
    case settings = "设置"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.grid.2x2"
        case .portfolio:
            return "briefcase"
        case .settings:
            return "gearshape"
        case .platform:
            return "chart.bar.xaxis"
        case .forum:
            return "text.bubble"
        }
    }
}

enum PersonalDataImportTarget: String, CaseIterable, Identifiable, Codable {
    case holdings = "持仓中"
    case pendingTrades = "买入中"
    case investmentPlans = "定投计划"

    var id: String { rawValue }

    var buttonTitle: String {
        switch self {
        case .holdings:
            return "保存持仓"
        case .pendingTrades:
            return "保存买入中"
        case .investmentPlans:
            return "保存计划"
        }
    }

    var sampleText: String {
        switch self {
        case .holdings:
            return "示例：021550 1200 1.1304；场内基金 510300 100 3.8；股票 600519 10 1500；港股 00700 100 350"
        case .pendingTrades:
            return "示例：2026-04-23 09:48:33 | 定投 | 019524 | 10.00元 | 交易进行中"
        case .investmentPlans:
            return "示例：定投 | 013308 | 每周三定投 | 500.00元 | 2 | 1000.00元 | 余额宝 | 2026-04-29(星期三) | 进行中"
        }
    }

    var helpText: String {
        switch self {
        case .holdings:
            return "支持 代码 份额 成本价 和 场内基金/股票/港股/美股 代码 数量 成本价 格式；ETF:、LOF:、EX: 或常见 ETF 前缀会归为场内基金。名称会保存时按代码自动补全。"
        case .pendingTrades:
            return "支持时间、动作、基金代码或名称、金额/份额、状态五列；保存时会按基金代码自动补全名称。"
        case .investmentPlans:
            return "支持计划类型、基金代码或名称、计划说明、金额、期数、累计、支付方式、下次时间，也支持“进行中 / 已暂停 / 已终止”状态。"
        }
    }
}

enum PersonalDataImportSource {
    case image
    case table

    var prepareSourceValue: String {
        switch self {
        case .image:
            return "ocr"
        case .table:
            return "table"
        }
    }
}

enum PersonalDataSaveMode: String, CaseIterable, Identifiable, Codable {
    case merge = "合并更新"
    case replace = "替换该类"

    var id: String { rawValue }

    var actionText: String {
        switch self {
        case .merge:
            return "合并"
        case .replace:
            return "替换"
        }
    }
}

enum PersonalAssetDeleteScope: String, CaseIterable, Identifiable {
    case holding
    case pendingTrades
    case investmentPlans
    case all

    var id: String { rawValue }

    var includesHolding: Bool {
        self == .holding || self == .all
    }

    var includesPendingTrades: Bool {
        self == .pendingTrades || self == .all
    }

    var includesInvestmentPlans: Bool {
        self == .investmentPlans || self == .all
    }
}

enum PersonalAssetUnitAdjustmentMode: String, Identifiable {
    case add
    case remove

    var id: String { rawValue }
}

struct PersonalAssetCodeResolution: Hashable {
    let assetType: PersonalAssetType
    let code: String
    let displayName: String?
    let stockMarket: StockMarket?
    let fundMarket: FundMarket?

    init(
        assetType: PersonalAssetType,
        code: String,
        displayName: String?,
        stockMarket: StockMarket? = nil,
        fundMarket: FundMarket? = nil
    ) {
        self.assetType = assetType
        self.code = code
        self.displayName = displayName
        self.stockMarket = stockMarket
        self.fundMarket = fundMarket
    }
}

extension PersonalDataImportTarget {
    var prepareTargetValue: String {
        switch self {
        case .holdings:
            return "holdings"
        case .pendingTrades:
            return "pending_trades"
        case .investmentPlans:
            return "investment_plans"
        }
    }
}

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

struct BootstrapPayload: Decodable {
    let status: StatusPayload
}

struct StatusPayload: Decodable {
    let cookieExists: Bool
    let cookieFile: String
    let outputDir: String
    let defaultForm: DefaultFormPayload
}

struct DefaultFormPayload: Decodable {
    let mode: String
    let prodCode: String
    let userName: String
    let pages: String
    let pageSize: String
}

struct FetchResponsePayload: Decodable {
    let snapshot: SnapshotPayload
}

struct SnapshotPayload: Decodable, Identifiable, Hashable {
    let fileName: String?
    let filePath: String?
    let snapshotType: String
    let kindLabel: String?
    let mode: String
    let title: String
    let subtitle: String
    let createdAt: String
    let count: Int
    let filters: [String: String]?
    let group: GroupPayload?
    let meta: SnapshotMetaPayload?
    let stats: SnapshotStatsPayload?
    let records: [SnapshotRecordPayload]
    let persisted: Bool?

    var id: String {
        fileName ?? "\(title)-\(createdAt)"
    }

    var displayTitle: String {
        title.isEmpty ? "未命名结果" : title
    }
}

struct GroupPayload: Decodable, Hashable {
    let groupId: Int?
    let groupName: String?
    let managerName: String?
    let managerBrokerUserId: String?
}

struct SnapshotMetaPayload: Decodable, Hashable {
    let mode: String?
}

struct SnapshotStatsPayload: Decodable, Hashable {
    let count: Int?
    let latestCreatedAt: String?
    let oldestCreatedAt: String?
    let uniqueUsers: Int?
    let uniqueGroups: Int?
    let totalLikes: Int?
    let totalComments: Int?
    let byDay: [DayBucketPayload]?
}

struct DayBucketPayload: Decodable, Hashable, Identifiable {
    let date: String
    let count: Int

    var id: String { date }
}

struct SnapshotRecordPayload: Decodable, Hashable, Identifiable {
    let groupId: Int?
    let groupName: String?
    let postId: Int?
    let brokerUserId: String?
    let spaceUserId: String?
    let userName: String?
    let userLabel: String?
    let userDesc: String?
    let createdAt: String?
    let managerName: String?
    let managerLabel: String?
    let groupDesc: String?
    let title: String?
    let intro: String?
    let contentText: String?
    let likeCount: Int?
    let commentCount: Int?
    let collectionCount: Int?
    let detailUrl: String?

    var id: String {
        if let postId, postId > 0 {
            return String(postId)
        }
        return firstNonEmpty([spaceUserId, brokerUserId, groupName, titleText, createdAt]) ?? "snapshot-record"
    }

    var titleText: String {
        let text = firstNonEmpty([
            plainText(title),
            plainText(intro),
            headlineText(from: plainText(contentText)),
            plainText(userName),
            plainText(groupName),
            plainText(managerName),
            plainText(brokerUserId),
        ]) ?? "未命名记录"
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    var bodyText: String {
        firstNonEmpty([
            plainText(contentText),
            plainText(intro),
            plainText(userDesc),
            plainText(groupDesc),
            plainText(userLabel),
            plainText(managerLabel),
        ]) ?? "无正文"
    }

    var metaText: String? {
        let value = [
            createdAt,
            userLabel,
            managerName.map { "主理人 \($0)" },
            groupName,
            brokerUserId.map { "broker \($0)" },
            spaceUserId.map { "space \($0)" },
        ]
        .compactMap { item -> String? in
            guard let item = item?.trimmingCharacters(in: .whitespacesAndNewlines), !item.isEmpty else {
                return nil
            }
            return item
        }
        .joined(separator: " · ")
        return value.isEmpty ? nil : value
    }

    var interactionText: String? {
        let parts = [
            likeCount.map { "赞 \($0)" },
            commentCount.map { "评 \($0)" },
            collectionCount.map { "藏 \($0)" },
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values.first(where: { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) ?? nil
    }

    private func headlineText(from value: String?) -> String? {
        guard let value else { return nil }
        let firstLine = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        guard !firstLine.isEmpty else { return nil }

        let sentenceEnders: [Character] = ["。", "！", "？", "；"]
        if let endIndex = firstLine.firstIndex(where: { sentenceEnders.contains($0) }) {
            return String(firstLine[...endIndex])
        }
        if firstLine.count > 56 {
            return String(firstLine.prefix(56)) + "..."
        }
        return firstLine
    }

    private func plainText(_ value: String?) -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        text = decodeCommonHTMLEntities(text)
        text = text
            .replacingOccurrences(of: #"(?i)<\s*br\s*/?\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</\s*(p|div|li|h[1-6]|blockquote)\s*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<\s*(p|div|li|h[1-6]|blockquote)[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<img[^>]*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        text = decodeCommonHTMLEntities(text)
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        let lines = text
            .components(separatedBy: .newlines)
            .map {
                $0
                    .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        let cleaned = lines.joined(separator: "\n\n")
        return cleaned.isEmpty ? nil : cleaned
    }

    private func decodeCommonHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

struct PlatformPayload: Decodable {
    let supported: Bool
    let prodCode: String?
    let count: Int?
    let buyCount: Int?
    let sellCount: Int?
    let adjustmentCount: Int?
    let latest: PlatformActionPayload?
    let actions: [PlatformActionPayload]?
    let holdings: PlatformHoldingsPayload?
    let timeline: [PlatformTimelinePayload]?
    let error: String?
}

struct PlatformActionPayload: Decodable, Hashable, Identifiable {
    let actionKey: String?
    let adjustmentId: Int?
    let adjustmentTitle: String?
    let title: String?
    let actionTitle: String?
    let fundName: String?
    let fundCode: String?
    let side: String?
    let action: String?
    let tradeUnit: Int?
    let postPlanUnit: Int?
    let createdAt: String?
    let txnDate: String?
    let createdTs: Int?
    let txnTs: Int?
    let articleUrl: String?
    let comment: String?
    let strategyType: String?
    let largeClass: String?
    let buyDate: String?
    let nav: Double?
    let navDate: String?
    let orderCountInAdjustment: Int?
    let tradeValuation: Double?
    let tradeValuationDate: String?
    let tradeValuationSource: String?
    let currentValuation: Double?
    let currentValuationTime: String?
    let currentValuationSource: String?
    let valuationChangeAmount: Double?
    let valuationChangePct: Double?

    var id: String {
        actionKey ?? "\(adjustmentId ?? 0)-\(fundCode ?? "")-\(txnDate ?? createdAt ?? "")"
    }

    var displayTitle: String {
        actionTitle ?? adjustmentTitle ?? title ?? fundName ?? fundCode ?? "未命名动作"
    }
}

struct PlatformHoldingsPayload: Decodable, Hashable {
    let assetCount: Int?
    let totalUnits: Int?
    let latestTime: String?
    let latestTs: Int?
    let items: [HoldingItemPayload]?
}

struct HoldingItemPayload: Decodable, Hashable, Identifiable {
    let assetKey: String?
    let label: String?
    let fundName: String?
    let fundCode: String?
    let currentUnits: Int?
    let latestAction: String?
    let latestActionTitle: String?
    let latestTime: String?
    let latestTs: Int?
    let strategyType: String?
    let largeClass: String?
    let buyDate: String?
    let avgCost: Double?
    let positionCost: Double?
    let currentPrice: Double?
    let priceSource: String?
    let priceSourceLabel: String?
    let priceTime: String?
    let officialNav: Double?
    let officialNavDate: String?
    let estimateChangePct: Double?
    let positionValue: Double?
    let profitRatio: Double?
    let costMethod: String?
    let costCoveredActions: Int?
    let costMissingActions: Int?
    let costReady: Bool?
    let quoteReady: Bool?
    let estimatedValue: Double?
    let profitAmount: Double?
    let profitPct: Double?

    var id: String {
        assetKey ?? fundCode ?? label ?? fundName ?? "unknown-holding"
    }

    var displayPositionValue: Double? {
        positionValue ?? estimatedValue
    }

    var displayProfitPct: Double? {
        profitRatio ?? profitPct
    }
}

struct PlatformTimelinePayload: Decodable, Hashable, Identifiable {
    let label: String
    let entries: [PlatformActionPayload]
    let buyCount: Int?
    let sellCount: Int?
    let eventCount: Int?
    let latestTime: String?
    let latestTs: Int?

    var id: String { label }
}

struct AuthCheckPayload: Decodable {
    let ok: Bool
    let message: String
    let userName: String
    let brokerUserId: String
    let userLabel: String
}

struct CommentsPayload: Decodable {
    let postId: Int
    let pageNum: Int
    let pageSize: Int
    let sortType: String
    let hasMore: Bool
    let comments: [CommentPayload]
}

struct CommentPayload: Decodable, Hashable, Identifiable {
    let id: Int
    let postId: Int?
    let userName: String?
    let userAvatarUrl: String?
    let brokerUserId: String?
    let content: String?
    let createdAt: String?
    let likeCount: Int?
    let replyCount: Int?
    let ipLocation: String?
    let toUserName: String?
    let children: [CommentPayload]
}

struct PlatformMonthSummary: Identifiable, Hashable {
    let month: String
    let totalCount: Int
    let buyCount: Int
    let sellCount: Int
    let activeDays: Int

    var id: String { month }

    var perActiveDayText: String {
        guard activeDays > 0 else { return "0.00" }
        return String(format: "%.2f", Double(totalCount) / Double(activeDays))
    }
}

enum PersonalAssetType: String, Codable, Hashable, Identifiable {
    case fund
    case stock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fund:
            return "基金"
        case .stock:
            return "股票"
        }
    }

    var draftPrefix: String? {
        switch self {
        case .fund:
            return nil
        case .stock:
            return "股票"
        }
    }
}

enum StockMarket: String, Codable, Hashable, CaseIterable {
    case aShare = "a"
    case hk = "hk"
    case us = "us"

    var displayName: String {
        switch self {
        case .aShare: return "A股"
        case .hk: return "港股"
        case .us: return "美股"
        }
    }

    var currencySymbol: String {
        switch self {
        case .aShare: return "¥"
        case .hk: return "HK$"
        case .us: return "$"
        }
    }
}

enum FundMarket: String, Codable, Hashable, CaseIterable {
    case offExchange = "off_exchange"
    case onExchange = "on_exchange"

    var displayName: String {
        switch self {
        case .offExchange:
            return "场外基金"
        case .onExchange:
            return "场内基金"
        }
    }
}

struct UserPortfolioHolding: Codable, Hashable, Identifiable {
    let id: UUID
    let fundCode: String
    let assetType: PersonalAssetType
    let units: Double
    let costPrice: Double?
    let displayName: String?
    let stockMarket: StockMarket?
    let fundMarket: FundMarket?
    let isArchived: Bool
    let archivedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fundCode
        case assetType
        case units
        case costPrice
        case displayName
        case stockMarket
        case fundMarket
        case isArchived
        case archivedAt
    }

    init(
        id: UUID = UUID(),
        fundCode: String,
        assetType: PersonalAssetType = .fund,
        units: Double,
        costPrice: Double?,
        displayName: String?,
        stockMarket: StockMarket? = nil,
        fundMarket: FundMarket? = nil,
        isArchived: Bool = false,
        archivedAt: String? = nil
    ) {
        self.id = id
        self.fundCode = fundCode
        self.assetType = assetType
        self.units = units
        self.costPrice = costPrice
        self.displayName = displayName
        self.stockMarket = stockMarket
        self.fundMarket = fundMarket
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.fundCode = try container.decode(String.self, forKey: .fundCode)
        self.assetType = try container.decodeIfPresent(PersonalAssetType.self, forKey: .assetType) ?? .fund
        self.units = try container.decode(Double.self, forKey: .units)
        self.costPrice = try container.decodeIfPresent(Double.self, forKey: .costPrice)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.stockMarket = try container.decodeIfPresent(StockMarket.self, forKey: .stockMarket)
        self.fundMarket = try container.decodeIfPresent(FundMarket.self, forKey: .fundMarket)
        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.archivedAt = try container.decodeIfPresent(String.self, forKey: .archivedAt)
    }

    var normalizedFundCode: String {
        fundCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedName: String? {
        let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var detectedMarket: StockMarket? {
        if let stockMarket { return stockMarket }
        guard assetType == .stock else { return nil }
        return UserPortfolioHolding.detectStockMarket(from: normalizedFundCode)
    }

    var detectedFundMarket: FundMarket? {
        guard assetType == .fund else { return nil }
        let inferredMarket = UserPortfolioHolding.detectFundMarket(from: normalizedFundCode)
        if fundMarket == .onExchange,
           inferredMarket == .offExchange,
           UserPortfolioHolding.isKnownOffExchangeFundCode(normalizedFundCode) {
            return .offExchange
        }
        return fundMarket ?? inferredMarket
    }

    var marketLabel: String? {
        if assetType == .stock {
            return detectedMarket?.displayName
        }
        return detectedFundMarket?.displayName
    }

    static func detectStockMarket(from code: String) -> StockMarket? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("SH") || trimmed.hasPrefix("SZ") || trimmed.hasPrefix("BJ") {
            return .aShare
        }
        if trimmed.hasPrefix("HK") {
            return .hk
        }
        if trimmed.hasPrefix("US") {
            return .us
        }
        if trimmed.count == 6, trimmed.allSatisfy(\.isNumber) {
            return .aShare
        }
        if trimmed.count == 5, trimmed.allSatisfy(\.isNumber) {
            return .hk
        }
        if trimmed.allSatisfy({ $0.isLetter }) {
            return .us
        }
        return nil
    }

    static func detectFundMarket(from code: String) -> FundMarket {
        let rawCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if rawCode.hasPrefix("ETF:") || rawCode.hasPrefix("LOF:") || rawCode.hasPrefix("EX:") {
            return .onExchange
        }
        if rawCode.hasPrefix("FUND:") || rawCode.hasPrefix("OTC:") {
            return .offExchange
        }
        let normalized = normalizedFundCode(from: code).uppercased()
        guard normalized.count == 6, normalized.allSatisfy(\.isNumber) else {
            return .offExchange
        }
        if isKnownOffExchangeFundCode(normalized) {
            return .offExchange
        }
        if isLikelyExchangeTradedFundCode(normalized) {
            return .onExchange
        }
        return .offExchange
    }

    static func isKnownOffExchangeFundCode(_ code: String) -> Bool {
        let normalized = normalizedFundCode(from: code).uppercased()
        return normalized.hasPrefix("519")
    }

    private static func isLikelyExchangeTradedFundCode(_ code: String) -> Bool {
        let normalized = normalizedFundCode(from: code).uppercased()
        let exchangePrefixes = ["15", "50", "52", "56", "58"]
        if exchangePrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }
        return normalized.hasPrefix("51") && !normalized.hasPrefix("519")
    }

    static func normalizedFundCode(from code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()
        for prefix in ["ETF:", "LOF:", "EX:", "FUND:", "OTC:"] where upper.hasPrefix(prefix) {
            return String(upper.dropFirst(prefix.count))
        }
        if upper.count == 8,
           (upper.hasPrefix("SH") || upper.hasPrefix("SZ") || upper.hasPrefix("BJ")),
           upper.dropFirst(2).allSatisfy(\.isNumber) {
            return String(upper.dropFirst(2))
        }
        if upper.count == 9,
           (upper.hasSuffix(".SH") || upper.hasSuffix(".SZ") || upper.hasSuffix(".BJ")),
           upper.prefix(6).allSatisfy(\.isNumber) {
            return String(upper.prefix(6))
        }
        return trimmed
    }

    var draftLine: String {
        var parts: [String] = []
        if assetType == .stock, let market = detectedMarket {
            parts.append(market.displayName)
        } else if assetType == .fund, let market = detectedFundMarket {
            parts.append(market.displayName)
        } else if let draftPrefix = assetType.draftPrefix {
            parts.append(draftPrefix)
        }
        parts.append(contentsOf: [normalizedFundCode, Self.decimalText(units)])
        if let costPrice {
            parts.append(Self.decimalText(costPrice))
        }
        if let normalizedName {
            parts.append(normalizedName)
        }
        return parts.joined(separator: " ")
    }

    private static func decimalText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

struct UserPortfolioValuationRow: Hashable, Identifiable {
    let holding: UserPortfolioHolding
    let fundName: String
    let currentPrice: Double?
    let priceTime: String?
    let priceSource: String?
    let officialNav: Double?
    let officialNavDate: String?
    let estimatePrice: Double?
    let estimatePriceTime: String?
    let marketValue: Double?
    let costValue: Double?
    let profitAmount: Double?
    let profitPct: Double?
    let estimateChangePct: Double?

    var id: UUID { holding.id }

    var resolvedPrice: Double? {
        currentPrice ?? officialNav
    }

    var resolvedPriceTime: String? {
        priceTime ?? officialNavDate
    }

    var resolvedPriceSource: String? {
        priceSource ?? (officialNav != nil ? "最新净值" : nil)
    }

    var estimatedMarketValue: Double? {
        guard let estimatePrice, holding.units > 0 else { return nil }
        return estimatePrice * holding.units
    }

    var previousMarketValue: Double? {
        guard
            let marketValue,
            let estimateChangePct
        else {
            return nil
        }
        let factor = 1 + estimateChangePct / 100
        guard factor > 0 else { return nil }
        return marketValue / factor
    }

    var estimatedDailyChangeAmount: Double? {
        if let estimatedMarketValue, let marketValue {
            return estimatedMarketValue - marketValue
        }
        guard
            let marketValue,
            let previousMarketValue
        else {
            return nil
        }
        return marketValue - previousMarketValue
    }
}

struct UserPortfolioDailyChangeSummary: Hashable {
    let amount: Double?
    let pct: Double?

    init(rows: [UserPortfolioValuationRow]) {
        var amountTotal = 0.0
        var amountCount = 0
        var pctChangeTotal = 0.0
        var pctPreviousTotal = 0.0

        for row in rows {
            guard let change = row.estimatedDailyChangeAmount else { continue }
            amountTotal += change
            amountCount += 1

            if let previous = row.previousMarketValue, previous > 0 {
                pctChangeTotal += change
                pctPreviousTotal += previous
            }
        }

        amount = amountCount > 0 ? amountTotal : nil
        pct = pctPreviousTotal > 0 ? pctChangeTotal / pctPreviousTotal * 100 : nil
    }
}

struct UserPortfolioSnapshot: Hashable {
    let rows: [UserPortfolioValuationRow]
    let refreshedAt: String
    let totalMarketValue: Double
    let totalCostValue: Double?
    let totalProfitAmount: Double?
    let totalProfitPct: Double?
    let dailyChangeSummary: UserPortfolioDailyChangeSummary

    var holdingCount: Int { rows.count }

    init(
        rows: [UserPortfolioValuationRow],
        refreshedAt: String,
        totalMarketValue: Double,
        totalCostValue: Double?,
        totalProfitAmount: Double?,
        totalProfitPct: Double?,
        dailyChangeSummary: UserPortfolioDailyChangeSummary? = nil
    ) {
        self.rows = rows
        self.refreshedAt = refreshedAt
        self.totalMarketValue = totalMarketValue
        self.totalCostValue = totalCostValue
        self.totalProfitAmount = totalProfitAmount
        self.totalProfitPct = totalProfitPct
        self.dailyChangeSummary = dailyChangeSummary ?? UserPortfolioDailyChangeSummary(rows: rows)
    }
}

struct PersonalPendingTrade: Codable, Hashable, Identifiable {
    let id: UUID
    let occurredAt: String
    let actionLabel: String
    let fundName: String
    let targetFundName: String?
    let fundCode: String?
    let targetFundCode: String?
    let amountText: String
    let amountValue: Double?
    let unitValue: Double?
    let status: String
    let note: String?

    init(
        id: UUID = UUID(),
        occurredAt: String,
        actionLabel: String,
        fundName: String,
        targetFundName: String? = nil,
        fundCode: String? = nil,
        targetFundCode: String? = nil,
        amountText: String,
        amountValue: Double? = nil,
        unitValue: Double? = nil,
        status: String,
        note: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.actionLabel = actionLabel
        self.fundName = fundName
        self.targetFundName = targetFundName
        self.fundCode = fundCode
        self.targetFundCode = targetFundCode
        self.amountText = amountText
        self.amountValue = amountValue
        self.unitValue = unitValue
        self.status = status
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case occurredAt
        case actionLabel
        case fundName
        case targetFundName
        case fundCode
        case targetFundCode
        case amountText
        case amountValue
        case unitValue
        case status
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.occurredAt = try container.decodeIfPresent(String.self, forKey: .occurredAt) ?? ""
        self.actionLabel = try container.decodeIfPresent(String.self, forKey: .actionLabel) ?? ""
        self.fundName = try container.decodeIfPresent(String.self, forKey: .fundName) ?? ""
        self.targetFundName = try container.decodeIfPresent(String.self, forKey: .targetFundName)
        self.fundCode = try container.decodeIfPresent(String.self, forKey: .fundCode)
        self.targetFundCode = try container.decodeIfPresent(String.self, forKey: .targetFundCode)
        self.amountText = try container.decodeIfPresent(String.self, forKey: .amountText) ?? ""
        self.amountValue = try container.decodeIfPresent(Double.self, forKey: .amountValue)
        self.unitValue = try container.decodeIfPresent(Double.self, forKey: .unitValue)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    var displayTitle: String {
        if let targetFundName, !targetFundName.isEmpty {
            return "\(fundName) -> \(targetFundName)"
        }
        return fundName
    }

    var displayCodeText: String? {
        if let fundCode, let targetFundCode, !targetFundCode.isEmpty {
            return "\(fundCode) -> \(targetFundCode)"
        }
        if let fundCode, !fundCode.isEmpty {
            return fundCode
        }
        return nil
    }

    var isCashTrade: Bool {
        amountValue != nil
    }
}

struct PersonalPendingTradeSummary: Hashable {
    let totalCashAmount: Double
    let cashTradeCount: Int
    let unitTradeCount: Int
    let latestTime: String?
    let actionCount: Int
}

struct PersonalInvestmentPlan: Codable, Hashable, Identifiable {
    let id: UUID
    let planTypeLabel: String
    let fundName: String
    let fundCode: String?
    let scheduleText: String
    let amountText: String
    let minAmount: Double?
    let maxAmount: Double?
    let investedPeriods: Int?
    let cumulativeInvestedAmount: Double?
    let paymentMethod: String?
    let nextExecutionDate: String
    let status: String
    let note: String?

    init(
        id: UUID = UUID(),
        planTypeLabel: String,
        fundName: String,
        fundCode: String? = nil,
        scheduleText: String,
        amountText: String,
        minAmount: Double? = nil,
        maxAmount: Double? = nil,
        investedPeriods: Int? = nil,
        cumulativeInvestedAmount: Double? = nil,
        paymentMethod: String? = nil,
        nextExecutionDate: String,
        status: String,
        note: String? = nil
    ) {
        self.id = id
        self.planTypeLabel = planTypeLabel
        self.fundName = fundName
        self.fundCode = fundCode
        self.scheduleText = scheduleText
        self.amountText = amountText
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.investedPeriods = investedPeriods
        self.cumulativeInvestedAmount = cumulativeInvestedAmount
        self.paymentMethod = paymentMethod
        self.nextExecutionDate = nextExecutionDate
        self.status = status
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id
        case planTypeLabel
        case fundName
        case fundCode
        case scheduleText
        case amountText
        case minAmount
        case maxAmount
        case investedPeriods
        case cumulativeInvestedAmount
        case paymentMethod
        case nextExecutionDate
        case status
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.planTypeLabel = try container.decodeIfPresent(String.self, forKey: .planTypeLabel) ?? ""
        self.fundName = try container.decodeIfPresent(String.self, forKey: .fundName) ?? ""
        self.fundCode = try container.decodeIfPresent(String.self, forKey: .fundCode)
        self.scheduleText = try container.decodeIfPresent(String.self, forKey: .scheduleText) ?? ""
        self.amountText = try container.decodeIfPresent(String.self, forKey: .amountText) ?? ""
        self.minAmount = try container.decodeIfPresent(Double.self, forKey: .minAmount)
        self.maxAmount = try container.decodeIfPresent(Double.self, forKey: .maxAmount)
        self.investedPeriods = try container.decodeIfPresent(Int.self, forKey: .investedPeriods)
        self.cumulativeInvestedAmount = try container.decodeIfPresent(Double.self, forKey: .cumulativeInvestedAmount)
        self.paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
        self.nextExecutionDate = try container.decodeIfPresent(String.self, forKey: .nextExecutionDate) ?? ""
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "进行中"
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    var isSmartPlan: Bool {
        planTypeLabel.contains("智能")
    }

    var isDrawdownMode: Bool {
        scheduleText.contains("涨跌幅")
    }

    var normalizedStatus: String {
        if status.contains("终止") {
            return "已终止"
        }
        if status.contains("暂停") {
            return "已暂停"
        }
        return "进行中"
    }

    var isActivePlan: Bool {
        normalizedStatus == "进行中"
    }

    var isPausedPlan: Bool {
        normalizedStatus == "已暂停"
    }

    var isEndedPlan: Bool {
        normalizedStatus == "已终止"
    }

    var isDailyPlan: Bool {
        scheduleText.contains("每日")
    }

    var isWeeklyPlan: Bool {
        scheduleText.contains("每周")
    }

    var amountRangeText: String {
        amountText
    }

    var normalizedAmountBounds: (min: Double?, max: Double?) {
        let parsed = Self.parsedAmountRange(from: amountText)
        let minValue = minAmount ?? parsed.min
        let maxValue = maxAmount ?? parsed.max
        switch (minValue, maxValue) {
        case let (min?, max?) where max < min:
            return (max, min)
        case let (min?, max?):
            return (min, max)
        case let (min?, nil):
            return (min, min)
        case let (nil, max?):
            return (max, max)
        default:
            return (nil, nil)
        }
    }

    var alipayBaseAmount: Double? {
        let bounds = normalizedAmountBounds
        switch (bounds.min, bounds.max) {
        case let (min?, max?) where abs(max - min) < 0.001:
            return min
        case let (min?, max?):
            let baseFromMax = max / 2
            if abs(min - baseFromMax * 0.5) <= Swift.max(0.01, baseFromMax * 0.01) {
                return baseFromMax
            }
            return (min + max) / 2
        case let (min?, nil):
            return min
        case let (nil, max?):
            return max
        default:
            return nil
        }
    }

    func estimatedExecutionAmount(costDeviationPct: Double?) -> Double {
        let bounds = normalizedAmountBounds
        guard let low = bounds.min else { return 0 }
        let high = bounds.max ?? low

        if !isDrawdownMode {
            if abs(high - low) < 0.001 {
                return low
            }
            return (low + high) / 2
        }

        guard let base = alipayBaseAmount else {
            return abs(high - low) < 0.001 ? low : (low + high) / 2
        }
        guard let costDeviationPct else {
            return clamped(base, min: low, max: high)
        }
        let multiplier = Self.alipayDrawdownMultiplier(for: costDeviationPct)
        return clamped(base * multiplier, min: low, max: high)
    }

    static func drawdownCostDeviationPct(currentPrice: Double?, costPrice: Double?) -> Double? {
        guard let currentPrice, let costPrice, costPrice > 0 else {
            return nil
        }
        return ((currentPrice - costPrice) / costPrice) * 100
    }

    static func alipayDrawdownMultiplier(for costDeviationPct: Double) -> Double {
        if costDeviationPct < 0 {
            return min(2.0, 1 + abs(costDeviationPct) * 0.08)
        }
        if costDeviationPct > 0 {
            return max(0.5, 1 - costDeviationPct * 0.04)
        }
        return 1
    }

    private func clamped(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private static func parsedAmountRange(from text: String) -> (min: Double?, max: Double?) {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "—", with: "~")
            .replacingOccurrences(of: "－", with: "~")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = cleaned
            .split { !"0123456789.".contains($0) }
            .compactMap { Double($0) }
        guard let first = numbers.first else {
            return (nil, nil)
        }
        if numbers.count >= 2, let second = numbers.dropFirst().first {
            return (first, second)
        }
        return (first, first)
    }
}

struct PersonalInvestmentPlanSummary: Hashable {
    let planCount: Int
    let activePlanCount: Int
    let pausedPlanCount: Int
    let endedPlanCount: Int
    let smartPlanCount: Int
    let dailyPlanCount: Int
    let weeklyPlanCount: Int
    let totalCumulativeInvestedAmount: Double
    let nextExecutionDate: String?
}

struct PersonalAssetAggregateRow: Identifiable, Hashable {
    let key: String
    let assetType: PersonalAssetType
    let fundName: String
    let fundCode: String?
    let holdingRow: UserPortfolioValuationRow?
    let rawHolding: UserPortfolioHolding?
    let archivedHolding: UserPortfolioHolding?
    let pendingTrades: [PersonalPendingTrade]
    let plans: [PersonalInvestmentPlan]
    let pendingCashAmount: Double
    let pendingUnitAmount: Double
    let activePlanCount: Int
    let pausedPlanCount: Int
    let endedPlanCount: Int
    let drawdownPlanCount: Int
    let totalCumulativePlanAmount: Double
    let estimatedNextPlanAmount: Double
    let nextExecutionDate: String?

    init(
        key: String,
        assetType: PersonalAssetType,
        fundName: String,
        fundCode: String?,
        holdingRow: UserPortfolioValuationRow?,
        rawHolding: UserPortfolioHolding?,
        archivedHolding: UserPortfolioHolding?,
        pendingTrades: [PersonalPendingTrade],
        plans: [PersonalInvestmentPlan]
    ) {
        self.key = key
        self.assetType = assetType
        self.fundName = fundName
        self.fundCode = fundCode
        self.holdingRow = holdingRow
        self.rawHolding = rawHolding
        self.archivedHolding = archivedHolding
        self.pendingTrades = pendingTrades
        self.plans = plans

        var pendingCashTotal = 0.0
        var pendingUnitTotal = 0.0
        for trade in pendingTrades {
            pendingCashTotal += trade.amountValue ?? 0
            pendingUnitTotal += trade.unitValue ?? 0
        }

        let drawdownDeviationPct = Self.drawdownCostDeviationPct(
            currentPrice: holdingRow?.resolvedPrice,
            costPrice: holdingRow?.holding.costPrice ?? rawHolding?.costPrice ?? archivedHolding?.costPrice
        )

        var activeCount = 0
        var pausedCount = 0
        var endedCount = 0
        var drawdownCount = 0
        var cumulativeAmount = 0.0
        var nextPlanAmount = 0.0
        var earliestExecutionDate: String?

        for plan in plans {
            switch plan.normalizedStatus {
            case "进行中":
                activeCount += 1
                nextPlanAmount += plan.estimatedExecutionAmount(costDeviationPct: drawdownDeviationPct)
                let executionDate = plan.nextExecutionDate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !executionDate.isEmpty,
                   earliestExecutionDate == nil || executionDate < earliestExecutionDate! {
                    earliestExecutionDate = executionDate
                }
            case "已暂停":
                pausedCount += 1
            case "已终止":
                endedCount += 1
            default:
                endedCount += 1
            }
            if plan.isDrawdownMode {
                drawdownCount += 1
            }
            cumulativeAmount += plan.cumulativeInvestedAmount ?? 0
        }

        pendingCashAmount = pendingCashTotal
        pendingUnitAmount = pendingUnitTotal
        activePlanCount = activeCount
        pausedPlanCount = pausedCount
        endedPlanCount = endedCount
        drawdownPlanCount = drawdownCount
        totalCumulativePlanAmount = cumulativeAmount
        estimatedNextPlanAmount = nextPlanAmount
        nextExecutionDate = earliestExecutionDate
    }

    var id: String { key }

    var assetTypeLabel: String {
        assetType.displayName
    }

    var detectedMarket: StockMarket? {
        rawHolding?.detectedMarket ?? holdingRow?.holding.detectedMarket ?? archivedHolding?.detectedMarket
    }

    var detectedFundMarket: FundMarket? {
        rawHolding?.detectedFundMarket
            ?? holdingRow?.holding.detectedFundMarket
            ?? archivedHolding?.detectedFundMarket
            ?? fundCode.map(UserPortfolioHolding.detectFundMarket)
    }

    var isOnExchangeFund: Bool {
        assetType == .fund && detectedFundMarket == .onExchange
    }

    var usesMarketTradeColumns: Bool {
        assetType == .stock || isOnExchangeFund
    }

    var marketValue: Double? {
        holdingRow?.marketValue
    }

    var holdingUnits: Double? {
        holdingRow?.holding.units ?? rawHolding?.units
    }

    var archivedUnits: Double? {
        archivedHolding?.units
    }

    var currentPrice: Double? {
        holdingRow?.resolvedPrice
    }

    var currentEstimatePrice: Double? {
        holdingRow?.estimatePrice
    }

    var currentEstimateMarketValue: Double? {
        holdingRow?.estimatedMarketValue
    }

    var costPrice: Double? {
        holdingRow?.holding.costPrice ?? rawHolding?.costPrice ?? archivedHolding?.costPrice
    }

    var profitAmount: Double? {
        holdingRow?.profitAmount
    }

    var profitPct: Double? {
        holdingRow?.profitPct
    }

    var estimateChangePct: Double? {
        holdingRow?.estimateChangePct
    }

    var estimateChangeAmount: Double? {
        holdingRow?.estimatedDailyChangeAmount
    }

    var pendingTradeCount: Int {
        pendingTrades.count
    }

    var totalPlanCount: Int {
        plans.count
    }

    var hasDrawdownPlan: Bool {
        drawdownPlanCount > 0
    }

    var effectiveHoldingAmount: Double {
        (marketValue ?? 0) + pendingCashAmount + estimatedNextPlanAmount
    }

    var hasHolding: Bool {
        marketValue != nil || holdingUnits != nil
    }

    var hasArchivedHolding: Bool {
        archivedHolding != nil
    }

    var hasPending: Bool {
        pendingTradeCount > 0
    }

    var hasPlans: Bool {
        totalPlanCount > 0
    }

    var combinedStatusText: String {
        var parts: [String] = []
        if hasHolding {
            parts.append("已持有")
        } else if hasArchivedHolding {
            parts.append("已归档")
        }
        if hasPending {
            parts.append("待确认")
        }
        if hasPlans {
            parts.append("计划中")
        }
        return parts.isEmpty ? "未归类" : parts.joined(separator: " + ")
    }

    private static func drawdownCostDeviationPct(currentPrice: Double?, costPrice: Double?) -> Double? {
        PersonalInvestmentPlan.drawdownCostDeviationPct(currentPrice: currentPrice, costPrice: costPrice)
    }
}

struct PersonalAssetAggregateSummary: Hashable {
    let fundCount: Int
    let holdingFundCount: Int
    let pendingFundCount: Int
    let activePlanFundCount: Int
    let totalMarketValue: Double
    let totalPendingCashAmount: Double
    let totalActivePlanCount: Int
    let totalPausedPlanCount: Int
    let totalEndedPlanCount: Int
    let totalCumulativePlanAmount: Double
    let totalEstimatedNextPlanAmount: Double
    let totalEffectiveHoldingAmount: Double
}
