import Foundation

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
    /// alfa 投顾线特有：调仓前后的持仓比例（0~1），长赢数据为 nil。
    let beforePercent: Double?
    let afterPercent: Double?
    /// alfa 投顾线特有：调仓分组名（如权益/债券），长赢数据为 nil。
    let groupName: String?
    /// alfa 投顾线特有：来源组合码（汇总筛选用），长赢数据为 nil。
    let sourcePoCode: String?

    init(
        actionKey: String?,
        adjustmentId: Int?,
        adjustmentTitle: String?,
        title: String?,
        actionTitle: String?,
        fundName: String?,
        fundCode: String?,
        side: String?,
        action: String?,
        tradeUnit: Int?,
        postPlanUnit: Int?,
        createdAt: String?,
        txnDate: String?,
        createdTs: Int?,
        txnTs: Int?,
        articleUrl: String?,
        comment: String?,
        strategyType: String?,
        largeClass: String?,
        buyDate: String?,
        nav: Double?,
        navDate: String?,
        orderCountInAdjustment: Int?,
        tradeValuation: Double?,
        tradeValuationDate: String?,
        tradeValuationSource: String?,
        currentValuation: Double?,
        currentValuationTime: String?,
        currentValuationSource: String?,
        valuationChangeAmount: Double?,
        valuationChangePct: Double?,
        beforePercent: Double? = nil,
        afterPercent: Double? = nil,
        groupName: String? = nil,
        sourcePoCode: String? = nil
    ) {
        self.actionKey = actionKey
        self.adjustmentId = adjustmentId
        self.adjustmentTitle = adjustmentTitle
        self.title = title
        self.actionTitle = actionTitle
        self.fundName = fundName
        self.fundCode = fundCode
        self.side = side
        self.action = action
        self.tradeUnit = tradeUnit
        self.postPlanUnit = postPlanUnit
        self.createdAt = createdAt
        self.txnDate = txnDate
        self.createdTs = createdTs
        self.txnTs = txnTs
        self.articleUrl = articleUrl
        self.comment = comment
        self.strategyType = strategyType
        self.largeClass = largeClass
        self.buyDate = buyDate
        self.nav = nav
        self.navDate = navDate
        self.orderCountInAdjustment = orderCountInAdjustment
        self.tradeValuation = tradeValuation
        self.tradeValuationDate = tradeValuationDate
        self.tradeValuationSource = tradeValuationSource
        self.currentValuation = currentValuation
        self.currentValuationTime = currentValuationTime
        self.currentValuationSource = currentValuationSource
        self.valuationChangeAmount = valuationChangeAmount
        self.valuationChangePct = valuationChangePct
        self.beforePercent = beforePercent
        self.afterPercent = afterPercent
        self.groupName = groupName
        self.sourcePoCode = sourcePoCode
    }

    var id: String {
        actionKey ?? "\(adjustmentId ?? 0)-\(fundCode ?? "")-\(txnDate ?? createdAt ?? "")"
    }

    var displayTitle: String {
        actionTitle ?? adjustmentTitle ?? title ?? fundName ?? fundCode ?? "未命名动作"
    }

    /// 是否为 alfa 投顾线的百分比调仓（区别于长赢的份数调仓）。
    var isPercentBased: Bool {
        beforePercent != nil || afterPercent != nil
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
