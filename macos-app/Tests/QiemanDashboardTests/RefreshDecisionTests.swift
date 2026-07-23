import XCTest
@testable import QiemanDashboard

final class RefreshDecisionTests: XCTestCase {
    func testOverviewSkipsWhenForumAndPlatformDataAreFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let decision = RefreshDecision.sectionTriggered(
            section: .overview,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-30),
            hasForumPosts: true,
            hasPlatformActions: true,
            hasPersonalPortfolio: true,
            hasPortfolioSnapshot: true,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )

        XCTAssertEqual(decision, .skip(reason: .freshDataAvailable))
    }

    func testOverviewRefreshesWhenRequiredDataIsMissingEvenIfLastRefreshIsFresh() {
        let now = Date(timeIntervalSince1970: 1_000)
        let decision = RefreshDecision.sectionTriggered(
            section: .overview,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-30),
            hasForumPosts: true,
            hasPlatformActions: false,
            hasPersonalPortfolio: true,
            hasPortfolioSnapshot: true,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )

        XCTAssertEqual(decision, .refreshLatest)
    }

    func testOverviewRefreshesWhenDataIsStaleEvenIfExistingDataIsPresent() {
        let now = Date(timeIntervalSince1970: 1_000)
        let decision = RefreshDecision.sectionTriggered(
            section: .overview,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-600),
            hasForumPosts: true,
            hasPlatformActions: true,
            hasPersonalPortfolio: true,
            hasPortfolioSnapshot: true,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )

        XCTAssertEqual(decision, .refreshLatest)
    }

    func testCombinedPlatformActivityRefreshesWhenEitherChildTabHasNoData() {
        let now = Date(timeIntervalSince1970: 1_000)
        let missingForum = RefreshDecision.sectionTriggered(
            section: .platform,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-30),
            hasForumPosts: false,
            hasPlatformActions: true,
            hasPersonalPortfolio: false,
            hasPortfolioSnapshot: false,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )
        let complete = RefreshDecision.sectionTriggered(
            section: .platform,
            now: now,
            lastLatestRefreshAt: now.addingTimeInterval(-30),
            hasForumPosts: true,
            hasPlatformActions: true,
            hasPersonalPortfolio: false,
            hasPortfolioSnapshot: false,
            isRefreshingLatest: false,
            isRefreshingPortfolio: false
        )

        XCTAssertEqual(missingForum, .refreshLatest)
        XCTAssertEqual(complete, .skip(reason: .freshDataAvailable))
    }

    func testPortfolioRefreshesWhenPortfolioSnapshotIsMissingOrStale() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                lastPortfolioRefreshAt: nil,
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: false,
                isRefreshingLatest: false,
                isRefreshingPortfolio: false
            ),
            .refreshPortfolio
        )

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                lastPortfolioRefreshAt: now.addingTimeInterval(-20),
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: true,
                isRefreshingLatest: false,
                isRefreshingPortfolio: false
            ),
            .skip(reason: .freshDataAvailable)
        )

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                lastPortfolioRefreshAt: now.addingTimeInterval(-600),
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: true,
                isRefreshingLatest: false,
                isRefreshingPortfolio: false
            ),
            .refreshPortfolio
        )
    }

    func testRefreshSkipsWhenSameOperationIsAlreadyInFlight() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .platform,
                now: now,
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: false,
                hasPortfolioSnapshot: false,
                isRefreshingLatest: true,
                isRefreshingPortfolio: false
            ),
            .skip(reason: .alreadyRefreshing)
        )

        XCTAssertEqual(
            RefreshDecision.sectionTriggered(
                section: .portfolio,
                now: now,
                hasForumPosts: false,
                hasPlatformActions: false,
                hasPersonalPortfolio: true,
                hasPortfolioSnapshot: false,
                isRefreshingLatest: false,
                isRefreshingPortfolio: true
            ),
            .skip(reason: .alreadyRefreshing)
        )
    }
}
