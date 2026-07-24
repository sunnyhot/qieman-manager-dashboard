import XCTest
@testable import QiemanDashboard

final class TradeSignalNotificationDecisionTests: XCTestCase {
    func testDecisionSendsSignalOncePerDay() {
        var state = TradeSignalNotificationState()
        let item = signal(status: .approaching, stale: false)
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作建议",
            generatedAt: "2026-07-03 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: false,
            items: [item]
        )
        let settings = settings(localNotificationsEnabled: true)

        let first = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings,
            state: state,
            day: "2026-07-03"
        )
        for request in first {
            state.markSent(request.key)
        }
        let second = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings,
            state: state,
            day: "2026-07-03"
        )

        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(second.isEmpty)
    }

    func testStatusUpgradeCanNotifyAgain() {
        var state = TradeSignalNotificationState()
        state.markSent("2026-07-03|000001|watchBuy|approaching")
        let upgraded = signal(status: .triggered, stale: false)
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作建议",
            generatedAt: "2026-07-03 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: false,
            items: [upgraded]
        )

        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings(localNotificationsEnabled: true),
            state: state,
            day: "2026-07-03"
        )

        XCTAssertEqual(requests.map(\.key), ["2026-07-03|000001|watchBuy|triggered"])
    }

    func testStaleAnalysisNotificationMentionsPreviousAnalysis() {
        let item = signal(status: .approaching, stale: true)
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作建议",
            generatedAt: "2026-07-02 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: true,
            items: [item]
        )

        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings(localNotificationsEnabled: true),
            state: TradeSignalNotificationState(),
            day: "2026-07-03"
        )

        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.body.contains("基于上次 AI 分析") == true)
        XCTAssertTrue(requests.first?.body.contains("打开 AI研判") == true)
    }

    func testDecisionSkipsWhenNotificationsDisabled() {
        let summary = TradeSignalSummary(
            headline: "1 条 AI 操作建议",
            generatedAt: "2026-07-03 09:30:00",
            dataAsOf: "2026-07-03 15:00:00",
            triggeredCount: 1,
            staleAnalysis: false,
            items: [signal(status: .approaching, stale: false)]
        )

        let requests = TradeSignalNotificationDecision.makeRequests(
            summary: summary,
            settings: settings(localNotificationsEnabled: false),
            state: TradeSignalNotificationState(),
            day: "2026-07-03"
        )

        XCTAssertTrue(requests.isEmpty)
    }

    func testWorkbenchTrendDeepLinkPayloadRoundTrips() {
        let payload = NotificationDeepLinkPayload(type: .workbenchTrend, targetID: "trade-signals")
        let decoded = NotificationDeepLinkPayload(userInfo: payload.userInfo)

        XCTAssertEqual(decoded?.type, .workbenchTrend)
        XCTAssertEqual(decoded?.targetID, "trade-signals")
    }

    private func signal(status: TradeSignalStatus, stale: Bool) -> TradeSignalItem {
        TradeSignalItem(
            id: "buy-000001",
            assetKey: "000001",
            assetName: "红利低波",
            assetCode: "000001",
            action: .watchBuy,
            status: status,
            confidence: TrendConfidence(score: 78, label: "中"),
            title: "关注买入红利低波",
            reason: stale ? "基于上次 AI 分析：回撤未破坏中期逻辑。" : "回撤未破坏中期逻辑。",
            triggerSummary: "继续回撤",
            invalidatingSummary: "趋势破位",
            dataAsOf: "2026-07-03 15:00:00",
            analysisGeneratedAt: stale ? "2026-07-02 09:30:00" : "2026-07-03 09:30:00",
            isBasedOnStaleAnalysis: stale,
            priority: 10
        )
    }

    private func settings(localNotificationsEnabled: Bool) -> TradeSignalSettings {
        TradeSignalSettings(
            enabled: true,
            localNotificationsEnabled: localNotificationsEnabled,
            riskPreference: .balanced,
            primaryHorizon: .medium,
            minimumConfidence: 60,
            allowBuySignals: true,
            allowSellSignals: true,
            useStaleAnalysis: true,
            assetPreferences: []
        )
    }
}
