import XCTest
@testable import QiemanDashboard

final class ManagerWatchTimelineTests: XCTestCase {
    func testSummaryOrdersEventsNewestFirst() {
        let old = event(kind: .pollStarted, occurredAt: date("2026-06-12T01:00:00Z"), title: "旧")
        let new = event(kind: .platformHit, occurredAt: date("2026-06-12T02:00:00Z"), title: "新")

        let summary = ManagerWatchTimelineSummary.make(events: [old, new])

        XCTAssertEqual(summary.events.map(\.title), ["新", "旧"])
        XCTAssertEqual(summary.latestStatusText, "新")
    }

    func testPruneKeepsMaxCountAndAge() {
        let now = date("2026-06-12T00:00:00Z")
        var events: [ManagerWatchTimelineEvent] = []
        for offset in 0..<205 {
            events.append(event(kind: .pollStarted, occurredAt: now.addingTimeInterval(TimeInterval(-offset * 60)), title: "\(offset)"))
        }
        events.append(event(kind: .failed, occurredAt: date("2026-02-01T00:00:00Z"), title: "过期"))

        let pruned = ManagerWatchTimelineStore.pruned(events, now: now, maxCount: 200, maxAgeDays: 90)

        XCTAssertEqual(pruned.count, 200)
        XCTAssertFalse(pruned.contains { $0.title == "过期" })
        XCTAssertEqual(pruned.first?.title, "0")
    }

    func testDuplicateSuppressionIsNotFailure() {
        let summary = ManagerWatchTimelineSummary.make(events: [
            event(kind: .duplicateSuppressed, title: "没有新发言")
        ])

        XCTAssertEqual(summary.failureCount, 0)
        XCTAssertEqual(summary.events.first?.tone, .info)
    }

    func testFailureAndRecoveryAffectSummary() {
        let failed = event(kind: .failed, occurredAt: date("2026-06-12T01:00:00Z"), title: "巡检失败", errorMessage: "网络错误")
        let recovered = event(kind: .recovered, occurredAt: date("2026-06-12T02:00:00Z"), title: "巡检恢复")

        let summary = ManagerWatchTimelineSummary.make(events: [failed, recovered])

        XCTAssertEqual(summary.latestStatusText, "巡检恢复")
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertEqual(summary.events.first?.tone, .positive)
        XCTAssertEqual(summary.events.last?.errorMessage, "网络错误")
    }

    func testStoreAppendPersistsAndPrunes() throws {
        let fileURL = try temporaryDirectory().appendingPathComponent("manager-watch-timeline.json")
        let store = ManagerWatchTimelineStore()

        try store.append(
            event(kind: .pollStarted, occurredAt: date("2026-06-12T00:00:00Z"), title: "开始"),
            to: fileURL,
            now: date("2026-06-12T00:00:00Z")
        )
        try store.append(
            event(kind: .platformHit, occurredAt: date("2026-06-12T00:01:00Z"), title: "命中调仓"),
            to: fileURL,
            now: date("2026-06-12T00:01:00Z")
        )

        let loaded = try store.load(from: fileURL)

        XCTAssertEqual(loaded.map(\.title), ["命中调仓", "开始"])
    }

    private func event(
        kind: ManagerWatchTimelineEventKind,
        occurredAt: Date = Date(timeIntervalSince1970: 1_781_217_600),
        title: String,
        errorMessage: String? = nil
    ) -> ManagerWatchTimelineEvent {
        ManagerWatchTimelineEvent(
            kind: kind,
            occurredAt: occurredAt,
            prodCode: "LONG_WIN",
            managerName: "ETF拯救世界",
            title: title,
            detail: "详情",
            targetID: nil,
            errorMessage: errorMessage
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("manager-watch-timeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
