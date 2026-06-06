import XCTest
@testable import QiemanDashboard

final class DashboardInsightTests: XCTestCase {
    func testFreshnessSummaryElevatesErrorsAndWarnings() {
        let context = DashboardFreshnessContext(
            cookieAvailable: false,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false,
            globalErrorMessage: "平台调仓刷新失败",
            hasPersonalPortfolio: true,
            portfolioRefreshedAt: nil,
            platformLatestTime: "2026-06-05 14:50",
            platformError: nil,
            forumLatestTime: nil,
            managerWatchEnabled: true,
            managerLastCheckedAt: "2026-06-05 14:55",
            managerLastSuccessAt: nil,
            managerError: "发言巡检失败"
        )

        let summary = DashboardFreshnessSummary.make(context: context)

        XCTAssertEqual(summary.headline, "3 个异常待处理")
        XCTAssertEqual(summary.items.prefix(3).map(\.kind), [.system, .managerWatch, .auth])
        XCTAssertEqual(summary.items.first?.tone, .error)
    }

    func testManagerActivitySummaryUsesLatestActionForumAndWatchStatus() {
        let context = ManagerActivityContext(
            managerName: "ETF拯救世界",
            prodCode: "LONG_WIN",
            latestPlatformTitle: "买入中证红利",
            latestPlatformTarget: "中证红利 ETF",
            latestPlatformTime: "2026-06-05",
            latestPlatformChangePct: 1.23,
            latestForumTitle: "本周组合观察",
            latestForumTime: "2026-06-05 09:30",
            latestForumInteraction: "赞 12 · 评 3",
            watchEnabled: true,
            watchScopeText: "LONG_WIN · ETF拯救世界 · 调仓 + 发言",
            lastSuccessAt: "2026-06-05 09:45",
            lastError: nil
        )

        let summary = ManagerActivitySummary.make(context: context)

        XCTAssertEqual(summary.title, "ETF拯救世界")
        XCTAssertEqual(summary.items.map(\.kind), [.platformAction, .forumRecord, .watchStatus])
        XCTAssertEqual(summary.items.first?.metric, "+1.23%")
        XCTAssertEqual(summary.items.last?.tone, .positive)
    }
}
