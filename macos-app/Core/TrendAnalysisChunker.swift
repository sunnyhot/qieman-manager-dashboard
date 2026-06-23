import Foundation

struct TrendAnalysisChunker {
    static let defaultChunkingThreshold = 35
    static let defaultChunkSize = 20

    let chunkingThreshold: Int
    let chunkSize: Int

    init(
        chunkingThreshold: Int = Self.defaultChunkingThreshold,
        chunkSize: Int = Self.defaultChunkSize
    ) {
        self.chunkingThreshold = max(1, chunkingThreshold)
        self.chunkSize = max(1, chunkSize)
    }

    func shouldChunk(_ context: TrendAnalysisContext) -> Bool {
        context.assets.count > chunkingThreshold
    }

    func chunks(from context: TrendAnalysisContext) -> [TrendAnalysisContext] {
        guard shouldChunk(context) else { return [context] }

        return stride(from: 0, to: context.assets.count, by: chunkSize).map { startIndex in
            let endIndex = min(startIndex + chunkSize, context.assets.count)
            let assets = Array(context.assets[startIndex..<endIndex])
            return context.replacingAssets(
                assets,
                sectors: sectors(for: assets, originalSectors: context.sectors)
            )
        }
    }

    func synthesisContext(from context: TrendAnalysisContext) -> TrendAnalysisContext {
        context.replacingAssets([], sectors: context.sectors)
    }

    private func sectors(
        for assets: [TrendContextAsset],
        originalSectors: [TrendContextSector]
    ) -> [TrendContextSector] {
        let assetCounts = Dictionary(grouping: assets, by: \.sector).mapValues(\.count)
        return originalSectors.compactMap { sector in
            guard let assetCount = assetCounts[sector.name] else { return nil }
            return TrendContextSector(
                name: sector.name,
                assetCount: assetCount,
                exposureText: sector.exposureText,
                exposureAmount: sector.exposureAmount
            )
        }
    }
}

private extension TrendAnalysisContext {
    func replacingAssets(
        _ assets: [TrendContextAsset],
        sectors: [TrendContextSector]
    ) -> TrendAnalysisContext {
        TrendAnalysisContext(
            createdAt: createdAt,
            privacyMode: privacyMode,
            portfolio: portfolio,
            assets: assets,
            sectors: sectors,
            platformSignals: platformSignals,
            watchSummary: watchSummary,
            insightHeadline: insightHeadline
        )
    }
}
