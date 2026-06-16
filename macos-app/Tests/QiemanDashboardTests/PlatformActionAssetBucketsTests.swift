import XCTest
@testable import QiemanDashboard

final class PlatformActionAssetBucketsTests: XCTestCase {
    func testBucketsFindLatestActionsWithoutSourceOrdering() {
        let actions = [
            action(id: "old-300", fundCode: "000300", title: "沪深300", postPlanUnit: 100, txnTs: 100),
            action(id: "latest-905", fundCode: "000905", title: "中证500", postPlanUnit: 5, txnTs: 150),
            action(id: "latest-300", fundCode: "000300", title: "沪深300", postPlanUnit: 0, txnTs: 200),
            action(id: "created-fallback", fundCode: "000001", title: "债券", postPlanUnit: 20, txnTs: nil, createdTs: 175)
        ]

        let buckets = PlatformActionAssetBuckets(actions: actions)

        XCTAssertEqual(buckets.latestByAsset["000300"]?.id, "latest-300")
        XCTAssertEqual(buckets.latestByAsset["000905"]?.id, "latest-905")
        XCTAssertEqual(buckets.latestByAsset["000001"]?.id, "created-fallback")
        XCTAssertEqual(buckets.sortedActions(for: "000300").map(\.id), ["old-300", "latest-300"])
    }

    private func action(
        id: String,
        fundCode: String,
        title: String,
        postPlanUnit: Int,
        txnTs: Int?,
        createdTs: Int? = nil
    ) -> PlatformActionPayload {
        PlatformActionPayload(
            actionKey: id,
            adjustmentId: nil,
            adjustmentTitle: title,
            title: title,
            actionTitle: title,
            fundName: title,
            fundCode: fundCode,
            side: "buy",
            action: "buy",
            tradeUnit: nil,
            postPlanUnit: postPlanUnit,
            createdAt: nil,
            txnDate: nil,
            createdTs: createdTs,
            txnTs: txnTs,
            articleUrl: nil,
            comment: nil,
            strategyType: nil,
            largeClass: nil,
            buyDate: nil,
            nav: nil,
            navDate: nil,
            orderCountInAdjustment: nil,
            tradeValuation: nil,
            tradeValuationDate: nil,
            tradeValuationSource: nil,
            currentValuation: nil,
            currentValuationTime: nil,
            currentValuationSource: nil,
            valuationChangeAmount: nil,
            valuationChangePct: nil
        )
    }
}
