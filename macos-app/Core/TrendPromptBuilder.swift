import Foundation

struct TrendModelPrompt: Hashable {
    let system: String
    let user: String
}

struct TrendPromptBuilder {
    func build(context: TrendAnalysisContext, settings: TrendAnalysisSettings) -> TrendModelPrompt {
        let contextJSON = encode(context)
        let system = baseSystemPrompt(settings: settings)

        let user = """
        Analyze the following Qieman portfolio context. Use short, medium, and long horizons. Return a single TrendAnalysisReport JSON object.

        Context JSON:
        \(contextJSON)
        """

        return TrendModelPrompt(system: system, user: user)
    }

    func buildChunk(
        context: TrendAnalysisContext,
        chunkIndex: Int,
        chunkCount: Int,
        settings: TrendAnalysisSettings
    ) -> TrendModelPrompt {
        let contextJSON = encode(context)
        let system = """
        \(baseSystemPrompt(settings: settings))
        This is a partial chunk analysis, not the final portfolio report.
        先判断板块趋势，再分析板块内关键资产，最后给出本板块的条件式行动候选。
        Treat sectors in this chunk as the primary analysis unit.
        Analyze only assets included in this chunk.
        Keep keyAssets and actions limited to this chunk's assets and 板块内关键资产.
        Do not output final whole-portfolio conclusions; leave whole-portfolio synthesis to the final merge step.
        """

        let user = """
        分块 \(chunkIndex)/\(chunkCount)：分析以下且慢组合的板块上下文。请先判断板块趋势，再筛选板块内关键资产，返回一个合法 TrendAnalysisReport JSON 对象，作为后续合成的局部报告。

        Context JSON:
        \(contextJSON)
        """

        return TrendModelPrompt(system: system, user: user)
    }

    func buildSynthesis(
        context: TrendAnalysisContext,
        chunkReports: [TrendAnalysisReport],
        settings: TrendAnalysisSettings
    ) -> TrendModelPrompt {
        let input = TrendChunkSynthesisInput(
            aggregateContext: context,
            chunkReports: chunkReports.map(TrendChunkReportDigest.init(report:))
        )
        let inputJSON = encode(input)
        let system = """
        \(baseSystemPrompt(settings: settings))
        Merge partial chunk reports into one final whole-portfolio TrendAnalysisReport.
        Deduplicate sectors, keyAssets, actions, evidence, and warnings.
        Use the aggregate portfolio context for counts and portfolio-level summaries.
        Do not introduce facts that are absent from the aggregate context or chunk reports.
        """

        let user = """
        请把以下分块报告合成为一个最终的 TrendAnalysisReport JSON 对象。最终结果要体现全组合视角，并保留不同板块、关键资产、行动候选和反向信号。

        分块报告与汇总上下文 JSON:
        \(inputJSON)
        """

        return TrendModelPrompt(system: system, user: user)
    }

    private func baseSystemPrompt(settings: TrendAnalysisSettings) -> String {
        let searchInstruction = settings.provider.supportsOnlineSearch
            ? "Use current online information when available and cite every external source."
            : "The selected provider is marked as not supporting online search; mark externalSignalStatus as unavailable unless evidence is already present in context."

        return """
        Return valid JSON only.
        Use the TrendAnalysisReport schema exactly.
        Separate facts, model judgment, and action candidates.
        \(searchInstruction)
        Do not invent sources.
        Do not guarantee returns.
        Do not use mandatory buy/sell language.
        Always include counterSignals, confidence, dataAsOf, generatedAt, evidence, warnings, and disclaimer.
        Every action candidate must include triggerConditions and invalidatingConditions.
        Use conditional Chinese wording such as 可考虑, 关注, 等待确认, 若...则....
        Do not use 必须买入, 必须卖出, 保证上涨, 保证收益, or 一定上涨.
        Required field names include portfolio, horizons, sectors, keyAssets, actions, evidence, warnings, disclaimer, counterSignals.
        """
    }

    private func encode(_ context: TrendAnalysisContext) -> String {
        encodeEncodable(context)
    }

    private func encode(_ input: TrendChunkSynthesisInput) -> String {
        encodeEncodable(input)
    }

    private func encodeEncodable<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct TrendChunkSynthesisInput: Encodable {
    let aggregateContext: TrendAnalysisContext
    let chunkReports: [TrendChunkReportDigest]
}

private struct TrendChunkReportDigest: Encodable {
    let generatedAt: String
    let externalSignalStatus: TrendExternalSignalStatus
    let portfolio: TrendPortfolioSummary
    let horizons: [TrendHorizonView]
    let sectors: [TrendSectorView]
    let keyAssets: [TrendAssetView]
    let actions: [TrendActionCandidate]
    let evidence: [TrendEvidence]
    let warnings: [TrendWarning]

    init(report: TrendAnalysisReport) {
        generatedAt = report.generatedAt
        externalSignalStatus = report.externalSignalStatus
        portfolio = report.portfolio
        horizons = report.horizons
        sectors = report.sectors
        keyAssets = report.keyAssets
        actions = report.actions
        evidence = Array(report.evidence.prefix(12))
        warnings = report.warnings
    }
}
