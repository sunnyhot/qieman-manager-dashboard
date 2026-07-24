import XCTest
@testable import QiemanDashboard

@MainActor
final class TrendTrackingTests: XCTestCase {

    func testStoreSaveLoadRoundTrip() throws {
        let url = try temporaryDirectory().appendingPathComponent("trend-tracking-items.json")
        let item = makeItem(assetKey: "F1", assetName: "基金A", action: .considerIncrease)
        try TrendTrackingStore().save([item], to: url)
        let loaded = try TrendTrackingStore().load(from: url)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.assetName, "基金A")
        XCTAssertEqual(loaded.first?.status, .observing)
        XCTAssertEqual(loaded.first?.triggerConditions, ["c"])
    }

    func testStoreLoadMissingFileReturnsEmpty() throws {
        let url = try temporaryDirectory().appendingPathComponent("missing.json")
        XCTAssertTrue(try TrendTrackingStore().load(from: url).isEmpty)
    }

    func testAddDedupesActiveSameAssetAction() {
        let model = AppModel()
        model.dataDirectoryURL = temporaryDirectory()
        let report = makeReport()
        let action = TrendActionCandidate(
            id: "a1", kind: .considerIncrease, title: "加仓A", detail: "理由",
            targetName: "基金A",
            confidence: TrendConfidence(score: 70, label: "中"),
            triggerConditions: ["c"], invalidatingConditions: ["d"]
        )
        XCTAssertTrue(model.addTrackingItem(from: action, report: report))
        XCTAssertEqual(model.trendTrackingItems.count, 1)
        // 同标的+动作再添加被忽略
        XCTAssertFalse(model.addTrackingItem(from: action, report: report))
        XCTAssertEqual(model.trendTrackingItems.count, 1)
    }

    func testStatusHistoryRecordedOnChange() {
        let model = AppModel()
        model.dataDirectoryURL = temporaryDirectory()
        addOne(to: model, name: "基金B", action: .watchSell)
        let id = model.trendTrackingItems[0].id
        XCTAssertEqual(model.trendTrackingItems[0].statusHistory.count, 1)
        model.markTrackingItem(id, status: .triggered, note: "手动标记已触发")
        XCTAssertEqual(model.trendTrackingItems[0].status, .triggered)
        XCTAssertEqual(model.trendTrackingItems[0].statusHistory.count, 2)
        XCTAssertEqual(model.trendTrackingItems[0].statusHistory.last?.to, .triggered)
        XCTAssertEqual(model.trendTrackingItems[0].statusHistory.last?.from, .observing)
    }

    func testSnoozeAndRecover() {
        let model = AppModel()
        model.dataDirectoryURL = temporaryDirectory()
        addOne(to: model, name: "基金C", action: .watchBuy)
        let id = model.trendTrackingItems[0].id
        model.snoozeTrackingItem(id, days: 1)
        XCTAssertEqual(model.trendTrackingItems[0].status, .processed)
        XCTAssertNotNil(model.trendTrackingItems[0].snoozeUntil)
        // 到期恢复
        let future = AppModel.timestampString(addingDays: 2)
        model.recoverSnoozedTrackingItems(now: future)
        XCTAssertEqual(model.trendTrackingItems[0].status, .observing)
        XCTAssertNil(model.trendTrackingItems[0].snoozeUntil)
    }

    func testResumeAndEnd() {
        let model = AppModel()
        model.dataDirectoryURL = temporaryDirectory()
        addOne(to: model, name: "基金D", action: .rebalanceReview)
        let id = model.trendTrackingItems[0].id
        model.snoozeTrackingItem(id, days: 7)
        model.resumeTrackingItem(id)
        XCTAssertEqual(model.trendTrackingItems[0].status, .observing)
        XCTAssertNil(model.trendTrackingItems[0].snoozeUntil)
        model.endTrackingItem(id)
        XCTAssertFalse(model.trendTrackingItems[0].isActive)
        // 结束后可重新加入同标的+动作
        let action = TrendActionCandidate(
            id: "a2", kind: .rebalanceReview, title: "再平衡D", detail: "x",
            targetName: "基金D",
            confidence: TrendConfidence(score: 60, label: "中"),
            triggerConditions: [], invalidatingConditions: []
        )
        XCTAssertTrue(model.addTrackingItem(from: action, report: makeReport()))
        XCTAssertEqual(model.trendTrackingItems.count, 2)
    }

    // MARK: - helpers

    private func addOne(to model: AppModel, name: String, action: TrendActionKind) {
        let candidate = TrendActionCandidate(
            id: "h-\(name)", kind: action, title: name, detail: "理由",
            targetName: name,
            confidence: TrendConfidence(score: 65, label: "中"),
            triggerConditions: [], invalidatingConditions: []
        )
        _ = model.addTrackingItem(from: candidate, report: makeReport())
    }

    private func makeReport() -> TrendAnalysisReport {
        TrendAnalysisReport.fixture(generatedAt: "2026-07-23 10:00:00", externalSignalStatus: .available)
    }

    private func makeItem(assetKey: String, assetName: String, action: TrendActionKind) -> TrendTrackingItem {
        TrendTrackingItem(
            sourceReportID: UUID(),
            sourceGeneratedAt: "2026-07-23 10:00:00",
            assetKey: assetKey,
            assetName: assetName,
            assetCode: nil,
            action: action,
            reason: "理由",
            confidence: TrendConfidence(score: 60, label: "中"),
            triggerConditions: ["c"],
            invalidatingConditions: ["d"],
            createdAt: "2026-07-23 10:00:00",
            status: .observing
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trend-track-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
