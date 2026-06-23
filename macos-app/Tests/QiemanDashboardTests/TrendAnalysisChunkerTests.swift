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

    func testLargeContextSplitsBySectorBeforeAssetCount() {
        let context = makeContext(sectorCounts: [
            ("A股", 16),
            ("美股", 14),
            ("场内基金", 12)
        ])
        let chunker = TrendAnalysisChunker()

        let chunks = chunker.chunks(from: context)

        XCTAssertEqual(chunks.map { $0.sectors.map(\.name) }, [["A股"], ["美股"], ["场内基金"]])
        XCTAssertEqual(chunks.map(\.assets.count), [16, 14, 12])
        XCTAssertEqual(Set(chunks[0].assets.map(\.sector)), ["A股"])
        XCTAssertEqual(Set(chunks[1].assets.map(\.sector)), ["美股"])
        XCTAssertEqual(Set(chunks[2].assets.map(\.sector)), ["场内基金"])
    }

    func testOversizedSectorKeepsSectorThenSplitsWithinIt() {
        let context = makeContext(sectorCounts: [
            ("A股", 42),
            ("美股", 6)
        ])
        let chunker = TrendAnalysisChunker()

        let chunks = chunker.chunks(from: context)

        XCTAssertEqual(chunks.map { $0.sectors.map(\.name) }, [["A股"], ["A股"], ["A股"], ["美股"]])
        XCTAssertEqual(chunks.map(\.assets.count), [20, 20, 2, 6])
        guard chunks.count == 4 else { return }
        XCTAssertEqual(Set(chunks[2].assets.map(\.sector)), ["A股"])
        XCTAssertEqual(Set(chunks[3].assets.map(\.sector)), ["美股"])
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
        makeContext(sectorCounts: [("场内基金", assetCount)])
    }

    private func makeContext(sectorCounts: [(name: String, count: Int)]) -> TrendAnalysisContext {
        var nextIndex = 0
        var assets: [TrendContextAsset] = []
        for sector in sectorCounts {
            for _ in 0..<sector.count {
                assets.append(makeAsset(index: nextIndex, sector: sector.name))
                nextIndex += 1
            }
        }

        return TrendAnalysisContext(
            createdAt: "2026-06-22 12:00:00",
            privacyMode: .sanitized,
            portfolio: TrendContextPortfolio(
                assetCount: assets.count,
                holdingCount: assets.count,
                activePlanCount: 0,
                pendingAssetCount: 0,
                totalMarketValue: nil,
                totalPendingCashAmount: nil,
                totalEstimatedNextPlanAmount: nil,
                totalEffectiveHoldingAmount: nil
            ),
            assets: assets,
            sectors: sectorCounts.map { sector in
                TrendContextSector(
                    name: sector.name,
                    assetCount: sector.count,
                    exposureText: "\(sector.count)项",
                    exposureAmount: nil
                )
            },
            platformSignals: [],
            watchSummary: "暂无",
            insightHeadline: "等待组合快照"
        )
    }

    private func makeAsset(index: Int, sector: String) -> TrendContextAsset {
        TrendContextAsset(
            id: "asset-\(index)",
            name: "测试基金\(index)",
            code: String(format: "51%04d", index),
            assetType: "基金",
            sector: sector,
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
}
