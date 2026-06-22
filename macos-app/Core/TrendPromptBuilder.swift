import Foundation

struct TrendModelPrompt: Hashable {
    let system: String
    let user: String
}

struct TrendPromptBuilder {
    func build(context: TrendAnalysisContext, settings: TrendAnalysisSettings) -> TrendModelPrompt {
        let contextJSON = encode(context)
        let searchInstruction = settings.provider.supportsOnlineSearch
            ? "Use current online information when available and cite every external source."
            : "The selected provider is marked as not supporting online search; mark externalSignalStatus as unavailable unless evidence is already present in context."

        let system = """
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

        let user = """
        Analyze the following Qieman portfolio context. Use short, medium, and long horizons. Return a single TrendAnalysisReport JSON object.

        Context JSON:
        \(contextJSON)
        """

        return TrendModelPrompt(system: system, user: user)
    }

    private func encode(_ context: TrendAnalysisContext) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(context) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
