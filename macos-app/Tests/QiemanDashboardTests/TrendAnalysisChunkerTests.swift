import XCTest
@testable import QiemanDashboard

final class TrendAnalysisChunkerTests: XCTestCase {
    func testLargeContextSplitsAssetsIntoStableChunks() {
        let context = makeContext(assetCount: 51)
        let chunker = TrendAnalysisChunker()

        let chunks = chunker.chunks(from: context)

        XCTAssertTrue(chunker.shouldChunk(context))
        XCTAssertEqual(chunks.map(\.assets.count), [20, 20, 11])
        XCTAssertEqual(chunks[0].assets.first?.id, "asset-0")
        XCTAssertEqual(chunks[1].assets.first?.id, "asset-20")
        XCTAssertEqual(chunks[2].assets.first?.id, "asset-40")
        XCTAssertEqual(chunks[0].portfolio.assetCount, 51)
        XCTAssertEqual(chunks[0].sectors.first?.assetCount, 20)
    }

    func testSmallContextKeepsSingleRequestShape() {
        let context = makeContext(assetCount: 35)
        let chunker = TrendAnalysisChunker()

        let chunks = chunker.chunks(from: context)

        XCTAssertFalse(chunker.shouldChunk(context))
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.assets.count, 35)
    }

    func testSynthesisContextDropsAssetDetailsButKeepsPortfolioSummary() {
        let context = makeContext(assetCount: 51)
        let synthesis = TrendAnalysisChunker().synthesisContext(from: context)

        XCTAssertTrue(synthesis.assets.isEmpty)
        XCTAssertEqual(synthesis.portfolio.assetCount, 51)
        XCTAssertEqual(synthesis.sectors.first?.assetCount, 51)
    }

    private func makeContext(assetCount: Int) -> TrendAnalysisContext {
        let assets = (0..<assetCount).map { index in
            TrendContextAsset(
                id: "asset-\(index)",
                name: "测试基金\(index)",
                code: String(format: "51%04d", index),
                assetType: "基金",
                sector: "场内基金",
                statusText: "持仓中",
                weightText: nil,
                profitPct: nil,
                estimateChangePct: nil,
                pendingTradeCount: 0,
                activePlanCount: 0,
                pausedPlanCount: 0,
                endedPlanCount: 0,
                marketValue: nil,
                costValue: nil,
                profitAmount: nil,
                pendingCashAmount: nil,
                estimatedNextPlanAmount: nil,
                totalCumulativePlanAmount: nil
            )
        }

        return TrendAnalysisContext(
            createdAt: "2026-06-22 12:00:00",
            privacyMode: .sanitized,
            portfolio: TrendContextPortfolio(
                assetCount: assetCount,
                holdingCount: assetCount,
                activePlanCount: 0,
                pendingAssetCount: 0,
                totalMarketValue: nil,
                totalPendingCashAmount: nil,
                totalEstimatedNextPlanAmount: nil,
                totalEffectiveHoldingAmount: nil
            ),
            assets: assets,
            sectors: [
                TrendContextSector(
                    name: "场内基金",
                    assetCount: assetCount,
                    exposureText: "100.00%",
                    exposureAmount: nil
                )
            ],
            platformSignals: [],
            watchSummary: "暂无",
            insightHeadline: "等待组合快照"
        )
    }
}
