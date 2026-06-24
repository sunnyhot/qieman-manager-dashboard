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
        let searchInstruction = """
        If the selected local agent has reliable external-signal access, include it with evidence.
        If not, set externalSignalStatus to partial or unavailable instead of inventing sources.
        Selected local agent: \(settings.agent.kind.displayName).
        """

        return """
        Return valid JSON only.
        Use the TrendAnalysisReport schema exactly.
        Read skill/instructions.md, skill/domain-rules.md, and skill/output-contract.md before writing output.
        Separate facts, model judgment, and action candidates.
        \(searchInstruction)
        Do not invent sources.
        Do not guarantee returns.
        Do not use mandatory buy/sell language.
        Do not perform exhaustive online searches for every asset; use broad market, sector, policy, and clearly material asset-level signals only.
        Keep keyAssets, actions, and evidence concise: prefer at most 5 keyAssets, 5 actions, and 6 evidence items in a final report, and at most 3 of each in chunk reports.
        If keyAssets.horizons is not empty, each item must use the same horizon object shape as top-level horizons: horizon, direction, confidence, rationale, and counterSignals.
        Always include counterSignals, confidence, dataAsOf, generatedAt, evidence, warnings, and disclaimer.
        Every action candidate must include triggerConditions and invalidatingConditions.
        Use conditional Chinese wording such as 可考虑, 关注, 等待确认, 若...则....
        Do not use 必须买入, 必须卖出, 保证上涨, 保证收益, or 一定上涨.
        Required field names include portfolio, horizons, sectors, keyAssets, actions, evidence, warnings, disclaimer, counterSignals.
        Do not add fields outside this schema. Do not output totalMarketValue, totalCostValue, totalProfit, assetCount, or top-level confidence in the report.
        Use this exact JSON shape. Keep id fields as stable strings when included, and keep all non-id keys present:
        {
          "generatedAt": "YYYY-MM-DD HH:mm:ss",
          "dataAsOf": "YYYY-MM-DD HH:mm:ss",
          "privacyMode": "脱敏摘要 or 完整明细",
          "externalSignalStatus": "available|unavailable|partial|stale",
          "portfolio": {
            "headline": "一句话组合判断",
            "riskLevel": "low|medium|high|unknown",
            "summary": "组合级解释"
          },
          "horizons": [
            {
              "horizon": "short|medium|long",
              "direction": "bullish|neutralPositive|neutral|neutralNegative|bearish|uncertain",
              "confidence": {"score": 0, "label": "低|中|高"},
              "rationale": "判断依据",
              "counterSignals": ["反证条件"]
            }
          ],
          "sectors": [
            {
              "name": "板块名称",
              "exposureText": "占比或暴露描述",
              "direction": "bullish|neutralPositive|neutral|neutralNegative|bearish|uncertain",
              "confidence": {"score": 0, "label": "低|中|高"},
              "rationale": "板块判断",
              "evidenceIDs": [],
              "counterSignals": []
            }
          ],
          "keyAssets": [
            {
              "name": "标的名称",
              "code": "代码或 null",
              "sector": "板块",
              "impactText": "对组合影响",
              "horizons": [],
              "rationale": "标的判断",
              "counterSignals": []
            }
          ],
          "actions": [
            {
              "kind": "watch|waitForConfirmation|observeInBatches|pausePlan|considerIncrease|considerReduce|rebalanceReview",
              "title": "动作标题",
              "detail": "条件式动作说明",
              "targetName": "对象或 null",
              "confidence": {"score": 0, "label": "低|中|高"},
              "triggerConditions": [],
              "invalidatingConditions": []
            }
          ],
          "evidence": [
            {
              "sourceName": "来源名称",
              "title": "证据标题",
              "url": "URL 或 null",
              "publishedAt": "发布时间或 null",
              "retrievedAt": "YYYY-MM-DD HH:mm:ss",
              "summary": "证据摘要"
            }
          ],
          "warnings": [
            {"title": "边界提示", "detail": "提示详情"}
          ],
          "disclaimer": "非投资建议，仅供个人研究参考。"
        }
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
