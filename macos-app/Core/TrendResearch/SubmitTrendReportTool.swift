import Foundation

// 阶段二：submit_trend_report 工具。
//
// 接收模型提交的完整报告，执行：解码 → 用快照覆盖 privacyMode/dataAsOf、用当前时间
// 覆盖 generatedAt → 证据归一化（只保留被引用且账本中存在的证据，用账本规范对象覆盖
// 模型填写字段）→ 调用增强后的 Validator。校验通过则返回 completion，Agent 结束；
// 校验失败则把错误回灌模型继续修正。

struct SubmitTrendReportTool: TrendResearchTool {
    let name = "submit_trend_report"
    let description = "提交最终趋势研究报告并结束本次分析。report 必须是完整的报告对象。证据只能引用工具返回的 evidence_ids，不得创造 URL 或来源标题。所有持有基金必须出现在 assetTrends。"
    let parameters: AgentJSONValue = [
        "type": "object",
        "properties": [
            "report": ["type": "object", "description": "完整的 TrendAnalysisReport 对象"]
        ],
        "required": ["report"],
        "additionalProperties": false
    ]

    func execute(argumentsJSON: String, context: TrendResearchToolContext) async -> TrendResearchToolResult {
        let snapshot = context.snapshot

        // 1. 取出 report 对象。
        guard let argumentsObject = try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any],
              let reportValue = argumentsObject["report"] else {
            return .content(TrendResearchToolEnvelope.error(code: "invalid_arguments", message: "缺少 report 字段或参数不是合法 JSON"), isError: true)
        }
        let reportData: Data
        do {
            reportData = try JSONSerialization.data(withJSONObject: reportValue)
        } catch {
            return .content(TrendResearchToolEnvelope.error(code: "invalid_arguments", message: "report 对象无法序列化：\(error.localizedDescription)"), isError: true)
        }

        // 2. 解码（自定义 init(from:) 对缺失字段宽容）。
        let decoded: TrendAnalysisReport
        do {
            decoded = try JSONDecoder().decode(TrendAnalysisReport.self, from: reportData)
        } catch {
            return validationFailure(messages: ["报告解码失败：\(Self.describeDecodingError(error))"], context: context)
        }

        // 3. 收集被引用的证据 ID（sectors/marketOutlook/opportunities）。
        let referencedIDs = Self.collectReferencedEvidenceIDs(decoded)

        // 4. 证据归一化：只保留被引用且账本中存在的证据，用账本规范对象覆盖模型字段。
        var canonical: [TrendEvidence] = []
        var seen = Set<String>()
        for id in referencedIDs {
            if seen.contains(id) { continue }
            guard let entry = await context.evidenceLedger.canonical(for: id) else { continue }
            seen.insert(id)
            canonical.append(entry)
        }

        // 5. 外部信号状态由 App 按最终实际引用的规范证据归一化，忽略模型自报值。
        let externalSignalStatus = Self.externalSignalStatus(for: canonical)

        // 6. 用快照覆盖 privacyMode（let，需重建）和 dataAsOf；用当前时间覆盖 generatedAt。
        let normalized = TrendAnalysisReport(
            id: decoded.id,
            generatedAt: Self.nowTimestamp(),
            dataAsOf: snapshot.dataAsOf,
            privacyMode: snapshot.privacyMode,
            externalSignalStatus: externalSignalStatus,
            portfolio: decoded.portfolio,
            horizons: decoded.horizons,
            marketOutlook: decoded.marketOutlook,
            sectors: decoded.sectors,
            opportunities: decoded.opportunities,
            keyAssets: decoded.keyAssets,
            assetTrends: decoded.assetTrends,
            actions: decoded.actions,
            evidence: canonical,
            warnings: decoded.warnings,
            disclaimer: decoded.disclaimer
        )

        // 7. 业务校验。
        let result = TrendAnalysisValidator().validate(
            normalized,
            expectedFundCodes: snapshot.expectedFundCodes,
            expectedPrivacyMode: snapshot.privacyMode
        )
        guard result.isValid else {
            return validationFailure(messages: result.messages, context: context)
        }

        // 8. 校验通过，返回报告，Agent 结束。
        let successEnvelope = TrendResearchToolEnvelope.success([
            "accepted": true,
            "generatedAt": normalized.generatedAt,
            "dataAsOf": normalized.dataAsOf
        ])
        return .report(successEnvelope, isError: false, report: normalized)
    }

    private func validationFailure(messages: [String], context: TrendResearchToolContext) -> TrendResearchToolResult {
        let remaining = max(0, context.invalidSubmissionBudget - context.invalidSubmissionsUsed - 1)
        let envelope = TrendResearchToolEnvelope.submitValidationError(
            code: "report_validation_failed",
            message: "报告未通过校验，请按 errors 修正后重新提交。",
            errors: messages,
            remainingRepairAttempts: remaining
        )
        return .content(envelope, isError: true)
    }

    private static func collectReferencedEvidenceIDs(_ report: TrendAnalysisReport) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        let append: (String) -> Void = { id in
            if !seen.contains(id) { seen.insert(id); ids.append(id) }
        }
        report.sectors.forEach { $0.evidenceIDs.forEach(append) }
        report.marketOutlook.forEach { $0.evidenceIDs.forEach(append) }
        report.opportunities.forEach { $0.evidenceIDs.forEach(append) }
        return ids
    }

    private static func externalSignalStatus(for evidence: [TrendEvidence]) -> TrendExternalSignalStatus {
        if evidence.contains(where: { $0.id.hasPrefix("web:tavily:") }) {
            return .available
        }
        if evidence.contains(where: { $0.id.hasPrefix("market:") }) {
            return .partial
        }
        return .unavailable
    }

    private static func nowTimestamp() -> String {
        Self.timestampFormatter.string(from: Date())
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "缺少字段 \(key.stringValue)\(codingPathSuffix(context.codingPath))"
        case .valueNotFound(_, let context):
            return "缺少必要值\(codingPathSuffix(context.codingPath))"
        case .typeMismatch(_, let context):
            return "字段类型不匹配\(codingPathSuffix(context.codingPath))"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func codingPathSuffix(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "" }
        return "（路径：\(path.map(\.stringValue).joined(separator: "."))）"
    }
}
