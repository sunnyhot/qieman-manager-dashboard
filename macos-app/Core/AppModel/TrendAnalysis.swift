import Foundation

extension AppModel {
    var enhancementTrendStatus: EnhancementTrendStatus {
        let generatedAt = lastTrendGeneratedAt ?? trendReport?.generatedAt
        let currentDay = trendDayString(from: Self.timestampString())
        let generatedDay = generatedAt.map { trendDayString(from: $0) }
        let stale = generatedDay.map { $0 != currentDay } ?? false
        let isProviderConfigured = trendSettings.provider.isConfigured
        let headline: String
        if let report = trendReport {
            headline = report.portfolio.headline
        } else if !lastTrendError.isEmpty {
            headline = lastTrendError
        } else {
            headline = isProviderConfigured ? "等待生成趋势分析" : "尚未配置趋势分析模型"
        }

        return EnhancementTrendStatus(
            isProviderConfigured: isProviderConfigured,
            generationState: trendGenerationState,
            lastGeneratedAt: generatedAt,
            headline: headline,
            externalSignalStatus: trendReport?.externalSignalStatus,
            isStale: stale
        )
    }

    var trendDashboardSummary: TrendDashboardSummary {
        TrendDashboardSummary.make(
            report: trendReport,
            trendStatus: enhancementTrendStatus,
            generationState: trendGenerationState,
            lastError: lastTrendError,
            progressLogs: trendProgressLogs
        )
    }

    func loadTrendAnalysisState() {
        if let trendAnalysisSettingsFileURL {
            do {
                trendSettings = try TrendAnalysisSettingsStore().load(from: trendAnalysisSettingsFileURL)
                trendPrivacyMode = trendSettings.defaultPrivacyMode
            } catch {
                lastTrendError = error.localizedDescription
            }
        }

        if let trendAnalysisReportFileURL {
            do {
                trendReport = try TrendAnalysisReportStore().load(from: trendAnalysisReportFileURL)
                lastTrendGeneratedAt = trendReport?.generatedAt
            } catch {
                lastTrendError = error.localizedDescription
            }
        }
    }

    func saveTrendAnalysisSettings() {
        guard let trendAnalysisSettingsFileURL else { return }
        do {
            try TrendAnalysisSettingsStore().save(trendSettings, to: trendAnalysisSettingsFileURL)
        } catch {
            lastTrendError = error.localizedDescription
        }
    }

    func saveTrendAnalysisReport(_ report: TrendAnalysisReport) {
        guard let trendAnalysisReportFileURL else { return }
        do {
            try TrendAnalysisReportStore().save(report, to: trendAnalysisReportFileURL)
        } catch {
            lastTrendError = error.localizedDescription
        }
    }

    func checkTrendAIConnection() async {
        guard trendSettings.provider.isConfigured else {
            trendConnectionState = .failed
            lastTrendConnectionMessage = TrendAIClientError.missingConfiguration.localizedDescription
            lastTrendError = lastTrendConnectionMessage
            return
        }

        saveTrendAnalysisSettings()
        trendConnectionState = .checking
        lastTrendConnectionMessage = "正在检测 \(trendSettings.provider.model)..."
        lastTrendError = ""

        do {
            let result = try await trendAIClient.checkConnection(settings: trendSettings.provider)
            trendConnectionState = .succeeded
            let preview = result.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = preview.isEmpty ? "" : " 返回：\(preview)"
            lastTrendConnectionMessage = "模型可用：\(result.model) · \(result.endpoint)。\(suffix)"
        } catch {
            trendConnectionState = .failed
            lastTrendConnectionMessage = error.localizedDescription
            lastTrendError = error.localizedDescription
        }
    }

    func generateTrendAnalysis(userInitiated: Bool, createdAt: String? = nil) async {
        guard trendSettings.provider.isConfigured else {
            trendGenerationState = .failed
            lastTrendError = TrendAIClientError.missingConfiguration.localizedDescription
            return
        }

        let generatedAt = createdAt ?? Self.timestampString()
        trendGenerationState = .generating
        lastTrendError = ""
        trendProgressLogs = []
        appendTrendProgress("开始趋势分析：\(trendSettings.provider.model)")
        appendTrendProgress("准备参数：\(trendPrivacyMode.rawValue) · 直连模型 · 超时 \(trendTimeoutText(trendSettings.provider))")
        trendSettings.defaultPrivacyMode = trendPrivacyMode

        let context = TrendAnalysisContextBuilder().build(
            rows: personalAssetRows,
            summary: personalAssetSummary,
            platformActions: latestPlatformActions,
            watchSummary: managerWatchTimelineSummary,
            insightSummary: portfolioSnapshotInsightSummary,
            privacyMode: trendPrivacyMode,
            createdAt: generatedAt
        )
        appendTrendProgress("构建趋势上下文：\(context.assets.count) 个标的，\(context.sectors.count) 个板块")
        appendTrendProgress("输入摘要", detail: trendContextSummary(context))

        do {
            let report = try await generateTrendReport(context: context, settings: trendSettings)
            appendTrendProgress("校验模型报告")
            let validation = TrendAnalysisValidator().validate(report)
            guard validation.isValid else {
                trendGenerationState = .rejected
                lastTrendError = validation.messages.joined(separator: "\n")
                appendTrendProgress("JSON 校验失败", detail: validation.messages.joined(separator: "\n"))
                appendTrendProgress("趋势分析被拦截：报告未通过安全校验")
                return
            }
            appendTrendProgress("JSON 校验通过", detail: "报告结构完整，可展示；已检查短中长期、行动触发条件、反证条件和非投资建议声明。")

            trendReport = report
            lastTrendGeneratedAt = report.generatedAt
            trendGenerationState = .succeeded
            if !userInitiated {
                trendSettings.lastAutoAnalysisDay = trendDayString(from: generatedAt)
            }
            appendTrendProgress("保存趋势报告")
            saveTrendAnalysisReport(report)
            saveTrendAnalysisSettings()
            appendTrendProgress("趋势分析完成")
        } catch {
            trendGenerationState = .failed
            lastTrendError = error.localizedDescription
            appendTrendProgress("趋势分析失败：\(error.localizedDescription)")
        }
    }

    func runDailyTrendAnalysisIfNeeded(createdAt: String? = nil) async {
        guard trendSettings.dailyAutoAnalysisEnabled else { return }
        guard trendSettings.provider.isConfigured else { return }

        let generatedAt = createdAt ?? Self.timestampString()
        let day = trendDayString(from: generatedAt)
        guard !trendSettings.hasAutoAnalyzed(on: day) else { return }

        await generateTrendAnalysis(userInitiated: false, createdAt: generatedAt)
    }

    private func trendDayString(from timestamp: String) -> String {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return trimmed }
        return String(trimmed.prefix(10))
    }

    private func generateTrendReport(
        context: TrendAnalysisContext,
        settings: TrendAnalysisSettings
    ) async throws -> TrendAnalysisReport {
        appendTrendProgress("单次模型分析：\(context.assets.count) 个标的，\(context.sectors.count) 个板块")
        appendTrendProgress("生成趋势提示词：\(context.privacyMode.rawValue)")
        return try await requestTrendReport(
            context: context,
            settings: settings,
            phase: "模型分析"
        )
    }

    private func requestTrendReport(
        context: TrendAnalysisContext,
        settings: TrendAnalysisSettings,
        phase: String
    ) async throws -> TrendAnalysisReport {
        let prompt = TrendPromptBuilder().build(context: context, settings: settings)
        appendTrendProgress("提示词摘要", detail: trendPromptSummary(prompt, context: context))
        let provider = settings.provider.upgradedForTrendGeneration
        appendTrendProgress("启动趋势模型：\(provider.model) · 超时 \(trendTimeoutText(provider))")
        let heartbeatTask = startTrendProgressHeartbeat(phase: phase)
        defer { heartbeatTask.cancel() }
        let start = Date()
        let report = try await trendAIClient.generateReport(prompt: prompt, settings: provider)
        appendTrendProgress("收到模型报告：\(provider.model) · \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
        appendTrendProgress("模型输出摘要", detail: trendReportSummary(report, expectedAssetCount: context.assets.count))
        return report
    }

    private func startTrendProgressHeartbeat(phase: String) -> Task<Void, Never> {
        let interval = trendProgressHeartbeatIntervalNanoseconds
        guard interval > 0 else { return Task {} }
        return Task { [weak self] in
            var elapsed = interval
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                self?.appendTrendProgress("等待模型返回：\(phase) 已等待 \(Self.trendElapsedText(elapsed))")
                elapsed += interval
            }
        }
    }

    private func appendTrendProgress(_ message: String, detail: String? = nil) {
        let entry = TrendProgressLog(timestamp: Self.timestampString(), message: message, detail: detail)
        trendProgressLogs.append(entry)
        if trendProgressLogs.count > 50 {
            trendProgressLogs.removeFirst(trendProgressLogs.count - 50)
        }
    }

    private func trendContextSummary(_ context: TrendAnalysisContext) -> String {
        let assetNames = context.assets.prefix(8).map { asset in
            if let code = asset.code, !code.isEmpty {
                return "\(asset.name)(\(code))"
            }
            return asset.name
        }
        let sectorNames = context.sectors.prefix(8).map(\.name)
        return [
            "资产：\(context.assets.count) 个；示例：\(assetNames.isEmpty ? "暂无" : assetNames.joined(separator: "、"))\(context.assets.count > assetNames.count ? " 等" : "")",
            "板块：\(context.sectors.count) 个；\(sectorNames.isEmpty ? "暂无" : sectorNames.joined(separator: "、"))",
            "组合：持仓 \(context.portfolio.holdingCount)，计划 \(context.portfolio.activePlanCount)，待确认 \(context.portfolio.pendingAssetCount)",
            "隐私：\(context.privacyMode.rawValue)；外部信号摘要：\(context.platformSignals.isEmpty ? "暂无" : "\(context.platformSignals.count) 条")"
        ].joined(separator: "\n")
    }

    private func trendPromptSummary(_ prompt: TrendModelPrompt, context: TrendAnalysisContext) -> String {
        [
            "system：\(prompt.system.count) 字符；user：\(prompt.user.count) 字符",
            "约束：返回合法 JSON；每个资产必须有 keyAssets；展示条件式买/持/卖；仅展示可核验分析轨迹",
            "上下文：\(context.assets.count) 个资产、\(context.sectors.count) 个板块、\(context.platformSignals.count) 条平台信号"
        ].joined(separator: "\n")
    }

    private func trendReportSummary(_ report: TrendAnalysisReport, expectedAssetCount: Int) -> String {
        let coverageText = "\(report.keyAssets.count)/\(expectedAssetCount)"
        let actionNames = report.actions.prefix(5).map { "\($0.kind.assetTagText)：\($0.title)" }
        return [
            "headline：\(report.portfolio.headline)",
            "risk：\(report.portfolio.riskLevel.rawValue)；external：\(report.externalSignalStatus.rawValue)",
            "keyAssets：\(coverageText)；sectors：\(report.sectors.count)；actions：\(report.actions.count)；evidence：\(report.evidence.count)",
            "动作：\(actionNames.isEmpty ? "暂无" : actionNames.joined(separator: "；"))"
        ].joined(separator: "\n")
    }

    private func trendTimeoutText(_ settings: TrendAIProviderSettings) -> String {
        "\(Int(settings.timeoutSeconds.rounded())) 秒"
    }

    private static func trendElapsedText(_ nanoseconds: UInt64) -> String {
        let seconds = max(1, Int((nanoseconds + 999_999_999) / 1_000_000_000))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m\(remainder)s"
    }
}
