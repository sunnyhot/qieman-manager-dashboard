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
