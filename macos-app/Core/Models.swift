import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case portfolio = "我的持仓"
    case importCenter = "导入中心"
    case platform = "平台调仓"
    case forum = "论坛发言"
    case snapshots = "历史快照"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.grid.2x2"
        case .portfolio:
            return "briefcase"
        case .importCenter:
            return "square.and.arrow.down"
        case .platform:
            return "chart.bar.xaxis"
        case .forum:
            return "text.bubble"
        case .snapshots:
            return "clock.arrow.circlepath"
        }
    }
}

enum PersonalDataImportTarget: String, CaseIterable, Identifiable {
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
            return "示例：021550 1200 1.1304；股票 600519 10 1500"
        case .pendingTrades:
            return "示例：2026-04-23 09:48:33 | 定投 | 019524 | 10.00元 | 交易进行中"
        case .investmentPlans:
            return "示例：定投 | 013308 | 每周三定投 | 500.00元 | 2 | 1000.00元 | 余额宝 | 2026-04-29(星期三) | 进行中"
        }
    }

    var helpText: String {
        switch self {
        case .holdings:
            return "支持“代码 份额 成本价”和“股票 代码 数量 成本价”；名称会保存时按代码自动补全，也支持上传图片或表格后自动填入草稿区。"
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
    let history: [SnapshotPayload]
    let preferredSnapshotName: String?
    let preferredSnapshot: SnapshotPayload?
}

struct StatusPayload: Decodable {
    let cookieExists: Bool
    let cookieFile: String
    let outputDir: String
    let snapshotCount: Int
    let latestSnapshot: SnapshotPayload?
    let preferredSnapshotName: String?
    let defaultForm: DefaultFormPayload
}

struct DefaultFormPayload: Decodable {
    let mode: String
    let prodCode: String
    let userName: String
    let pages: String
    let pageSize: String
}

struct HistoryPayload: Decodable {
    let items: [SnapshotPayload]
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
        title.isEmpty ? "未命名快照" : title
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

enum PersonalAssetType: String, Codable, Hashable {
    case fund
    case stock

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

struct UserPortfolioHolding: Codable, Hashable, Identifiable {
    let id: UUID
    let fundCode: String
    let assetType: PersonalAssetType
    let units: Double
    let costPrice: Double?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fundCode
        case assetType
        case units
        case costPrice
        case displayName
    }

    init(id: UUID = UUID(), fundCode: String, assetType: PersonalAssetType = .fund, units: Double, costPrice: Double?, displayName: String?) {
        self.id = id
        self.fundCode = fundCode
        self.assetType = assetType
        self.units = units
        self.costPrice = costPrice
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.fundCode = try container.decode(String.self, forKey: .fundCode)
        self.assetType = try container.decodeIfPresent(PersonalAssetType.self, forKey: .assetType) ?? .fund
        self.units = try container.decode(Double.self, forKey: .units)
        self.costPrice = try container.decodeIfPresent(Double.self, forKey: .costPrice)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
    }

    var normalizedFundCode: String {
        fundCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedName: String? {
        let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var draftLine: String {
        var parts: [String] = []
        if let draftPrefix = assetType.draftPrefix {
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
        guard
            let marketValue,
            let previousMarketValue
        else {
            return nil
        }
        return marketValue - previousMarketValue
    }
}

struct UserPortfolioSnapshot: Hashable {
    let rows: [UserPortfolioValuationRow]
    let refreshedAt: String
    let totalMarketValue: Double
    let totalCostValue: Double?
    let totalProfitAmount: Double?
    let totalProfitPct: Double?

    var holdingCount: Int { rows.count }
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
    let pendingTrades: [PersonalPendingTrade]
    let plans: [PersonalInvestmentPlan]

    var id: String { key }

    var assetTypeLabel: String {
        assetType.displayName
    }

    var marketValue: Double? {
        holdingRow?.marketValue
    }

    var holdingUnits: Double? {
        holdingRow?.holding.units ?? rawHolding?.units
    }

    var currentPrice: Double? {
        holdingRow?.resolvedPrice
    }

    var costPrice: Double? {
        holdingRow?.holding.costPrice ?? rawHolding?.costPrice
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

    var pendingCashAmount: Double {
        pendingTrades.compactMap(\.amountValue).reduce(0, +)
    }

    var pendingUnitAmount: Double {
        pendingTrades.compactMap(\.unitValue).reduce(0, +)
    }

    var pendingTradeCount: Int {
        pendingTrades.count
    }

    var activePlans: [PersonalInvestmentPlan] {
        plans.filter(\.isActivePlan)
    }

    var pausedPlans: [PersonalInvestmentPlan] {
        plans.filter(\.isPausedPlan)
    }

    var endedPlans: [PersonalInvestmentPlan] {
        plans.filter(\.isEndedPlan)
    }

    var activePlanCount: Int {
        activePlans.count
    }

    var pausedPlanCount: Int {
        pausedPlans.count
    }

    var endedPlanCount: Int {
        endedPlans.count
    }

    var totalPlanCount: Int {
        plans.count
    }

    var drawdownPlanCount: Int {
        plans.filter(\.isDrawdownMode).count
    }

    var hasDrawdownPlan: Bool {
        drawdownPlanCount > 0
    }

    var totalCumulativePlanAmount: Double {
        plans.compactMap(\.cumulativeInvestedAmount).reduce(0, +)
    }

    var estimatedNextPlanAmount: Double {
        activePlans.reduce(0) { partial, plan in
            partial + estimatedNextPlanAmount(for: plan)
        }
    }

    var effectiveHoldingAmount: Double {
        (marketValue ?? 0) + pendingCashAmount + estimatedNextPlanAmount
    }

    var nextExecutionDate: String? {
        activePlans
            .map(\.nextExecutionDate)
            .filter { !$0.isEmpty }
            .sorted()
            .first
    }

    var hasHolding: Bool {
        marketValue != nil || holdingUnits != nil
    }

    var hasPending: Bool {
        pendingTradeCount > 0
    }

    var hasPlans: Bool {
        totalPlanCount > 0
    }

    var combinedStatusText: String {
        switch (hasHolding, hasPending, hasPlans) {
        case (true, true, true):
            return "已持有 + 待确认 + 计划中"
        case (true, true, false):
            return "已持有 + 待确认"
        case (true, false, true):
            return "已持有 + 计划中"
        case (false, true, true):
            return "待确认 + 计划中"
        case (true, false, false):
            return "已持有"
        case (false, true, false):
            return "待确认"
        case (false, false, true):
            return "计划中"
        default:
            return "未归类"
        }
    }

    private func estimatedNextPlanAmount(for plan: PersonalInvestmentPlan) -> Double {
        let amountRange = normalizedAmountRange(for: plan)
        guard let low = amountRange.min else { return 0 }
        let high = amountRange.max ?? low

        if !plan.isDrawdownMode {
            if abs(high - low) < 0.001 {
                return low
            }
            return (low + high) / 2
        }

        guard let changePct = estimateChangePct else {
            return abs(high - low) < 0.001 ? low : (low + high) / 2
        }
        if changePct < 0 {
            return high
        }
        if changePct > 0 {
            return low
        }
        return abs(high - low) < 0.001 ? low : (low + high) / 2
    }

    private func normalizedAmountRange(for plan: PersonalInvestmentPlan) -> (min: Double?, max: Double?) {
        let parsed = parsedAmountRange(from: plan.amountText)
        let minValue = plan.minAmount ?? parsed.min
        let maxValue = plan.maxAmount ?? parsed.max
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

    private func parsedAmountRange(from text: String) -> (min: Double?, max: Double?) {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "元", with: "")
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
