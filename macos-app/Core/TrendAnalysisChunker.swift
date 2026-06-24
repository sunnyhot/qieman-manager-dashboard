import Foundation

struct TrendAnalysisChunker {
    static let defaultChunkingThreshold = 18
    static let defaultChunkSize = 10

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

        return sectorAssetGroups(from: context).flatMap { group in
            stride(from: 0, to: group.assets.count, by: chunkSize).map { startIndex in
                let endIndex = min(startIndex + chunkSize, group.assets.count)
                let assets = Array(group.assets[startIndex..<endIndex])
                return context.replacingAssets(
                    assets,
                    sectors: sectors(for: assets, originalSectors: context.sectors)
                )
            }
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

    private func sectorAssetGroups(from context: TrendAnalysisContext) -> [TrendSectorAssetGroup] {
        let groupedAssets = Dictionary(grouping: context.assets, by: \.sector)
        var usedSectorNames: Set<String> = []
        var groups: [TrendSectorAssetGroup] = []

        for sector in context.sectors {
            guard let assets = groupedAssets[sector.name], !assets.isEmpty else { continue }
            groups.append(TrendSectorAssetGroup(name: sector.name, assets: assets))
            usedSectorNames.insert(sector.name)
        }

        let fallbackGroups = groupedAssets
            .filter { !usedSectorNames.contains($0.key) }
            .map { TrendSectorAssetGroup(name: $0.key, assets: $0.value) }
            .sorted { lhs, rhs in
                if lhs.assets.count == rhs.assets.count {
                    return lhs.name < rhs.name
                }
                return lhs.assets.count > rhs.assets.count
            }
        return groups + fallbackGroups
    }
}

private struct TrendSectorAssetGroup {
    let name: String
    let assets: [TrendContextAsset]
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
