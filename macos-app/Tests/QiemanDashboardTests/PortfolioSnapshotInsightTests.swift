import XCTest
@testable import QiemanDashboard

final class PortfolioSnapshotInsightTests: XCTestCase {
    func testSummaryReportsInsufficientHistory() {
        let summary = PortfolioSnapshotInsightSummary.make(snapshots: [], currentRows: [])

        XCTAssertFalse(summary.hasEnoughHistory)
        XCTAssertEqual(summary.headline, "等待组合快照")
        XCTAssertTrue(summary.cards.contains { $0.kind == .coverage })
    }

    func testSummaryComputesAssetChangeAndGainTone() {
        let snapshots = [
            snapshot(createdAt: "2026-06-11 15:00:00", totalExposure: 10_000, topWeight: 60),
            snapshot(createdAt: "2026-06-12 15:00:00", totalExposure: 12_500, topWeight: 55)
        ]

        let summary = PortfolioSnapshotInsightSummary.make(snapshots: snapshots, currentRows: [])

        XCTAssertTrue(summary.hasEnoughHistory)
        XCTAssertEqual(summary.headline, "组合占用增加 ¥2,500.00")
        XCTAssertEqual(summary.cards.first { $0.kind == .assetChange }?.tone, .gain)
    }

    func testSummaryComputesConcentrationDrift() {
        let snapshots = [
            snapshot(createdAt: "2026-06-11 15:00:00", totalExposure: 10_000, topWeight: 35),
            snapshot(createdAt: "2026-06-12 15:00:00", totalExposure: 10_000, topWeight: 48)
        ]

        let summary = PortfolioSnapshotInsightSummary.make(snapshots: snapshots, currentRows: [])

        XCTAssertEqual(summary.cards.first { $0.kind == .concentrationDrift }?.metric, "+13.00 pct")
        XCTAssertEqual(summary.cards.first { $0.kind == .concentrationDrift }?.tone, .warning)
    }

    func testSummaryIncludesPlanAndPendingImpactFromCurrentRows() {
        let rows = [
            row(name: "核心宽基", code: "000001", pendingAmount: 500, nextPlanAmount: 200)
        ]
        let snapshots = [
            snapshot(createdAt: "2026-06-11 15:00:00", totalExposure: 10_000, topWeight: 40),
            snapshot(createdAt: "2026-06-12 15:00:00", totalExposure: 10_700, topWeight: 41)
        ]

        let summary = PortfolioSnapshotInsightSummary.make(snapshots: snapshots, currentRows: rows)

        XCTAssertEqual(summary.cards.first { $0.kind == .pendingImpact }?.metric, "¥500.00")
        XCTAssertEqual(summary.cards.first { $0.kind == .planImpact }?.metric, "¥200.00")
    }

    func testStoreRecordsAndPrunesSnapshots() throws {
        let fileURL = try temporaryDirectory().appendingPathComponent("portfolio-insight-snapshots.json")
        let store = PortfolioSnapshotInsightStore()
        var snapshots: [PortfolioInsightSnapshot] = []
        for index in 0..<40 {
            snapshots.append(snapshot(createdAt: String(format: "2026-06-%02d 15:00:00", index + 1), totalExposure: Double(index), topWeight: 10))
        }

        try store.save(snapshots, to: fileURL)
        let loaded = try store.load(from: fileURL)

        XCTAssertEqual(loaded.count, 30)
        XCTAssertEqual(loaded.first?.createdAt, "2026-06-11 15:00:00")
        XCTAssertEqual(loaded.last?.createdAt, "2026-06-40 15:00:00")
    }

    private func snapshot(createdAt: String, totalExposure: Double, topWeight: Double) -> PortfolioInsightSnapshot {
        PortfolioInsightSnapshot(
            createdAt: createdAt,
            totalExposure: totalExposure,
            totalMarketValue: totalExposure,
            pendingAmount: 0,
            nextPlanAmount: 0,
            topHoldingName: "核心宽基",
            topHoldingWeightPct: topWeight,
            holdingCount: 1
        )
    }

    private func row(name: String, code: String, pendingAmount: Double, nextPlanAmount: Double) -> PersonalAssetAggregateRow {
        let holding = UserPortfolioHolding(fundCode: code, assetType: .fund, units: 100, costPrice: 1, displayName: name)
        let pendingTrades = [
            PersonalPendingTrade(
                occurredAt: "2026-06-12",
                actionLabel: "买入",
                fundName: name,
                fundCode: code,
                amountText: "\(pendingAmount)",
                amountValue: pendingAmount,
                status: "交易进行中"
            )
        ]
        let plans = [
            PersonalInvestmentPlan(
                planTypeLabel: "定投",
                fundName: name,
                fundCode: code,
                scheduleText: "每周三",
                amountText: "\(nextPlanAmount)",
                minAmount: nextPlanAmount,
                maxAmount: nextPlanAmount,
                nextExecutionDate: "2026-06-17",
                status: "进行中"
            )
        ]
        return PersonalAssetAggregateRow(
            key: code,
            assetType: .fund,
            fundName: name,
            fundCode: code,
            holdingRow: nil,
            rawHolding: holding,
            archivedHolding: nil,
            pendingTrades: pendingTrades,
            plans: plans
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("portfolio-snapshot-insight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
