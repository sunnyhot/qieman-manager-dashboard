import Foundation

struct TrendModelPrompt: Hashable {
    let system: String
    let user: String
}

struct TrendPromptBuilder {
    func build(
        context: TrendAnalysisContext,
        settings: TrendAnalysisSettings,
        tradeSignalSettings: TradeSignalSettings = .default
    ) -> TrendModelPrompt {
        let contextJSON = encode(context)
        let system = baseSystemPrompt(settings: settings, tradeSignalSettings: tradeSignalSettings)

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
        settings: TrendAnalysisSettings,
        tradeSignalSettings: TradeSignalSettings = .default
    ) -> TrendModelPrompt {
        let contextJSON = encode(context)
        let system = """
        \(baseSystemPrompt(settings: settings, tradeSignalSettings: tradeSignalSettings))
        This is a partial chunk analysis, not the final portfolio report.
        先判断大盘与大类资产，再判断板块趋势，并逐个分析本分块内每个已持有基金，最后给出本板块的重点条件式行动候选。
        保留分块分析顺序：先判断板块趋势，再落到本分块基金。
        Treat sectors in this chunk as the primary analysis unit.
        Analyze only assets included in this chunk.
        Include every held fund in this chunk in assetTrends.
        Include every material asset in this chunk in keyAssets. Use assetTrends and sector rationale for low-importance holdings instead of forcing every asset into keyAssets.
        Keep actions limited to this chunk's重点动作; do not create one action per asset unless truly necessary.
        Do not output final whole-portfolio conclusions; leave whole-portfolio synthesis to the final merge step.
        """

        let user = """
        分块 \(chunkIndex)/\(chunkCount)：分析以下且慢组合的板块上下文。请先判断大盘/大类资产与板块趋势，再逐个覆盖本分块资产和每个已持有基金，返回一个合法 TrendAnalysisReport JSON 对象，作为后续合成的局部报告。

        Context JSON:
        \(contextJSON)
        """

        return TrendModelPrompt(system: system, user: user)
    }

    func buildSynthesis(
        context: TrendAnalysisContext,
        chunkReports: [TrendAnalysisReport],
        settings: TrendAnalysisSettings,
        tradeSignalSettings: TradeSignalSettings = .default
    ) -> TrendModelPrompt {
        let input = TrendChunkSynthesisInput(
            aggregateContext: context,
            chunkReports: chunkReports.map(TrendChunkReportDigest.init(report:))
        )
        let inputJSON = encode(input)
        let system = """
        \(baseSystemPrompt(settings: settings, tradeSignalSettings: tradeSignalSettings))
        Merge partial chunk reports into one final whole-portfolio TrendAnalysisReport.
        Deduplicate marketOutlook, sectors, opportunities, keyAssets, assetTrends, actions, evidence, and warnings.
        Use the aggregate portfolio context for counts and portfolio-level summaries.
        Do not introduce facts that are absent from the aggregate context or chunk reports.
        Preserve assetTrends coverage for every held fund in the aggregate context.
        Preserve only the strongest portfolio-relevant keyAssets from chunk reports; do not synthesize low-importance assets merely to fill coverage.
        """

        let user = """
        请把以下分块报告合成为一个最终的 TrendAnalysisReport JSON 对象。最终结果要体现全组合视角，并保留不同板块、关键资产、行动候选和反向信号。

        分块报告与汇总上下文 JSON:
        \(inputJSON)
        """

        return TrendModelPrompt(system: system, user: user)
    }

    private func baseSystemPrompt(
        settings: TrendAnalysisSettings,
        tradeSignalSettings: TradeSignalSettings
    ) -> String {
        let externalSignalInstruction = settings.provider.supportsOnlineSearch
            ? "If the selected model has reliable external-signal access, include concise evidence. If access is partial, set externalSignalStatus to partial instead of inventing sources."
            : "The selected model is configured without online search. Set externalSignalStatus to unavailable or partial, and do not invent external sources."
        let tradeSignalInstruction = tradeSignalPreferenceInstruction(tradeSignalSettings)

        return """
        Return valid JSON only.
        Use the TrendAnalysisReport schema exactly.
        Follow the embedded Qieman investment trend analysis skill rules in this prompt.
        Analyze Qieman portfolio data from a personal research perspective.
        Focus on conditional trend judgment, broad market and sector direction, portfolio risk boundaries, counter-signals, and watch/review actions.
        Separate facts, model judgment, and action candidates.
        \(externalSignalInstruction)
        Selected model: \(settings.provider.model).
        Do not invent sources.
        Do not guarantee returns.
        Do not use mandatory buy/sell language.
        所有面向用户的中文字段必须使用普通投资者能直接听懂的自然中文。
        不要使用或堆砌研报术语，包括 Beta、Alpha、动能、量能、产业周期、景气度、基本面寻底、估值修复、风险偏好、中枢、支撑位；确需表达时，改写成日常说法。
        rationale、impactText、summary、detail、triggerConditions、invalidatingConditions 和 counterSignals 必须写成完整句子，明确说明发生了什么、意味着什么，不要输出“AI产业周期”“行业 Beta 向下”这类名词短语。
        例如：不要写“纳斯达克科技巨头盈利动能强劲”，应写“纳斯达克大型科技公司的盈利仍在较快增长”；不要写“地产链条基本面仍在寻底”，应写“地产行业还没有明显企稳”。
        动作标题也要使用自然中文，例如写“继续持有”“先不操作”“考虑减仓”，不要写“买入观察”“减仓复核”“暂停追买”。
        对 keyAssets 和 assetTrends，首个 horizon.rationale 要用一句简短自然中文概括主要原因，可直接作为小标题；asset rationale 再用一到两句完整的话解释原因和影响。
        Do not perform exhaustive online searches for every asset; use broad market, sector, policy, and clearly material asset-level signals only.
        \(tradeSignalInstruction)
        marketOutlook must summarize 大盘 and major asset classes relevant to the portfolio, such as A-share broad indices, Hong Kong equities, US equities, bonds, commodities, and gold/黄金 when material.
        opportunities must capture still-actionable investment opportunities outside or across current holdings, including gold/黄金 when it has a clear conditional setup.
        assetTrends must include 每个已持有基金 from Context JSON, with a concise trend view and conditional buy/hold/sell execution guidance for each fund.
        keyAssets should focus on portfolio-relevant assets that materially affect trend judgment, concentration, pending cash, active plans, or risk.
        Do not force every Context JSON asset into keyAssets; use assetTrends, sectors, and warnings for low-importance or uncovered holdings.
        Every keyAsset and assetTrends impactText or rationale must include conditional buy/hold/sell execution guidance such as 分批买入, 持有观察, 暂停买入, 分批卖出, 再平衡复核, with trigger and counter-signal boundaries in horizons or counterSignals.
        Keep actions and evidence concise: actions are portfolio-level重点动作 only, preferably at most 5 actions in a final report and at most 3 actions in chunk reports; do not omit keyAssets just to keep actions short.
        Prefer one concise buy/hold/sell execution guidance per keyAsset over adding a separate action for every asset.
        Keep evidence concise: prefer at most 6 evidence items in a final report and at most 3 evidence items in chunk reports.
        If keyAssets.horizons is not empty, each item must use the same horizon object shape as top-level horizons: horizon, direction, confidence, rationale, and counterSignals.
        Always include counterSignals, confidence, dataAsOf, generatedAt, evidence, warnings, and disclaimer.
        Every action candidate must include triggerConditions and invalidatingConditions.
        Use conditional Chinese wording such as 可考虑, 关注, 等信号再动, 等待触发条件, 若...则....
        Do not use 必须买入, 必须卖出, 保证上涨, 保证收益, or 一定上涨.
        Required field names include portfolio, horizons, marketOutlook, sectors, opportunities, keyAssets, assetTrends, actions, evidence, warnings, disclaimer, counterSignals.
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
          "marketOutlook": [
            {
              "name": "大盘或大类资产名称",
              "category": "大盘宽基|港股|美股|债券|商品|黄金|其他",
              "direction": "bullish|neutralPositive|neutral|neutralNegative|bearish|uncertain",
              "confidence": {"score": 0, "label": "低|中|高"},
              "rationale": "大盘或大类资产判断",
              "evidenceIDs": [],
              "counterSignals": []
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
          "opportunities": [
            {
              "name": "机会名称",
              "category": "机会类别，如 黄金/商品/宽基/债券/现金管理",
              "direction": "bullish|neutralPositive|neutral|neutralNegative|bearish|uncertain",
              "confidence": {"score": 0, "label": "低|中|高"},
              "rationale": "为什么仍值得跟踪",
              "triggerConditions": [],
              "invalidatingConditions": [],
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
          "assetTrends": [
            {
              "name": "已持有基金名称",
              "code": "代码或 null",
              "sector": "板块",
              "impactText": "对组合影响和条件式买/持/卖执行建议",
              "horizons": [],
              "rationale": "基金趋势判断",
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

    private func tradeSignalPreferenceInstruction(_ settings: TradeSignalSettings) -> String {
        let assetText: String
        if settings.assetPreferences.isEmpty {
            assetText = "无单标的覆盖"
        } else {
            assetText = settings.assetPreferences
                .map { preference in
                    let horizon = preference.preferredHorizon.map { "；周期：\($0.displayText)" } ?? ""
                    let notes = preference.notes.isEmpty ? "" : "；备注：\(preference.notes)"
                    return "\(preference.assetKey)：\(preference.mode.displayText)\(horizon)\(notes)"
                }
                .joined(separator: "\n")
        }

        return """
        AI 操作建议偏好：
        - 启用：\(settings.enabled ? "是" : "否")
        - 风险偏好：\(settings.riskPreference.displayText)
        - 主要观察周期：\(settings.primaryHorizon.displayText)
        - 最低关注置信度：\(settings.minimumConfidence)
        - 允许关注买入：\(settings.allowBuySignals ? "是" : "否")
        - 允许关注卖出：\(settings.allowSellSignals ? "是" : "否")
        - 单标的偏好：
        \(assetText)
        These preferences influence prioritization and wording only. They do not authorize automatic trading and must not change the required JSON schema.
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
    let marketOutlook: [TrendMarketOutlook]
    let sectors: [TrendSectorView]
    let opportunities: [TrendOpportunity]
    let keyAssets: [TrendAssetView]
    let assetTrends: [TrendAssetView]
    let actions: [TrendActionCandidate]
    let evidence: [TrendEvidence]
    let warnings: [TrendWarning]

    init(report: TrendAnalysisReport) {
        generatedAt = report.generatedAt
        externalSignalStatus = report.externalSignalStatus
        portfolio = report.portfolio
        horizons = report.horizons
        marketOutlook = report.marketOutlook
        sectors = report.sectors
        opportunities = report.opportunities
        keyAssets = report.keyAssets
        assetTrends = report.assetTrends
        actions = report.actions
        evidence = Array(report.evidence.prefix(12))
        warnings = report.warnings
    }
}
