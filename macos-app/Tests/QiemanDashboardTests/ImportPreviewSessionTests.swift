import XCTest
@testable import QiemanDashboard

final class ImportPreviewSessionTests: XCTestCase {
    func testHoldingsPreviewGroupsAddedUpdatedUnchangedAndDuplicate() {
        let store = UserPortfolioStore()
        let existing = [
            holding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, code: "000001", units: 100, cost: 1),
            holding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, code: "000002", units: 200, cost: 2)
        ]
        let imported = [
            holding(code: "000001", units: 150, cost: 1),
            holding(code: "000002", units: 200, cost: 2),
            holding(code: "000003", units: 300, cost: 3),
            holding(code: "000003", units: 300, cost: 3)
        ]

        let session = ImportPreviewSession.makeHoldings(imported: imported, existing: existing, mode: .merge, store: store)

        XCTAssertEqual(session.count(for: .updated), 1)
        XCTAssertEqual(session.count(for: .unchanged), 1)
        XCTAssertEqual(session.count(for: .added), 1)
        XCTAssertEqual(session.count(for: .duplicate), 1)
        XCTAssertTrue(session.canConfirm)
    }

    func testReplacePreviewMarksRemovedExistingRows() {
        let store = PendingTradesStore()
        let existing = [
            trade(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, code: "000001", amount: "100.00元"),
            trade(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, code: "000002", amount: "200.00元")
        ]
        let imported = [
            trade(code: "000001", amount: "150.00元")
        ]

        let session = ImportPreviewSession.makePendingTrades(imported: imported, existing: existing, mode: .replace, store: store)

        XCTAssertEqual(session.count(for: .updated), 1)
        XCTAssertEqual(session.count(for: .removed), 1)
    }

    func testEmptyImportIsBlocked() {
        let session = ImportPreviewSession.makeInvestmentPlans(
            imported: [],
            existing: [],
            mode: .merge,
            store: InvestmentPlansStore()
        )

        XCTAssertFalse(session.canConfirm)
        XCTAssertEqual(session.count(for: .blocked), 1)
    }

    func testUndoSnapshotIsValidOnlyForExpectedAfterState() {
        let beforeHoldings = [holding(code: "000001", units: 100, cost: 1)]
        let afterHoldings = [holding(code: "000001", units: 150, cost: 1)]
        let snapshot = ImportUndoSnapshot.make(
            target: .holdings,
            mode: .merge,
            createdAt: "2026-06-12 10:30:00",
            beforeHoldings: beforeHoldings,
            beforePendingTrades: [],
            beforeInvestmentPlans: [],
            afterHoldings: afterHoldings,
            afterPendingTrades: [],
            afterInvestmentPlans: []
        )

        XCTAssertTrue(snapshot.isValid(currentHoldings: afterHoldings, currentPendingTrades: [], currentInvestmentPlans: []))
        XCTAssertFalse(snapshot.isValid(currentHoldings: beforeHoldings, currentPendingTrades: [], currentInvestmentPlans: []))
        XCTAssertEqual(snapshot.restoreHoldings, beforeHoldings)
    }

    private func holding(id: UUID = UUID(), code: String, units: Double, cost: Double) -> UserPortfolioHolding {
        UserPortfolioHolding(id: id, fundCode: code, assetType: .fund, units: units, costPrice: cost, displayName: "基金\(code)")
    }

    private func trade(id: UUID = UUID(), code: String, amount: String) -> PersonalPendingTrade {
        PersonalPendingTrade(
            id: id,
            occurredAt: "2026-06-12 10:00:00",
            actionLabel: "买入",
            fundName: "基金\(code)",
            fundCode: code,
            amountText: amount,
            amountValue: Double(amount.replacingOccurrences(of: "元", with: "")),
            status: "交易进行中"
        )
    }
}
