import Foundation

extension AppModel {
    var enhancementTrendStatus: EnhancementTrendStatus {
        let generatedAt = lastTrendGeneratedAt ?? trendReport?.generatedAt
        let currentDay = trendDayString(from: Self.timestampString())
        let generatedDay = generatedAt.map { trendDayString(from: $0) }
        let stale = generatedDay.map { $0 != currentDay } ?? false
        let headline: String
        if let report = trendReport {
            headline = report.portfolio.headline
        } else if !lastTrendError.isEmpty {
            headline = lastTrendError
        } else {
            headline = trendSettings.provider.isConfigured ? "等待生成趋势分析" : "尚未连接趋势分析模型"
        }

        return EnhancementTrendStatus(
            isProviderConfigured: trendSettings.provider.isConfigured,
            generationState: trendGenerationState,
            lastGeneratedAt: generatedAt,
            headline: headline,
            externalSignalStatus: trendReport?.externalSignalStatus,
            isStale: stale
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

        detectLocalAIConfigurations()
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

    func detectLocalAIConfigurations() {
        trendLocalCandidates = LocalAIConfigurationDetector().detect()
    }

    func importTrendProvider(_ candidate: LocalAIConfigurationCandidate) {
        guard let imported = candidate.importedSettings() else {
            lastTrendError = candidate.warning ?? "当前配置不能直接导入趋势分析模型。"
            return
        }

        trendSettings.provider = imported
        if trendPrivacyMode != trendSettings.defaultPrivacyMode {
            trendSettings.defaultPrivacyMode = trendPrivacyMode
        }
        lastTrendError = ""
        saveTrendAnalysisSettings()
    }

    func checkTrendAIConnection() async {
        guard trendSettings.provider.isConfigured else {
            trendConnectionState = .failed
            lastTrendConnectionMessage = "趋势分析模型配置不完整，请先填写 Base URL、模型和 API Key。"
            return
        }

        trendConnectionState = .checking
        lastTrendConnectionMessage = "正在检测 \(trendSettings.provider.model)..."
        lastTrendError = ""

        do {
            let result = try await trendAIClient.checkConnection(settings: trendSettings.provider)
            trendConnectionState = .succeeded
            let preview = result.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = preview.isEmpty ? "" : " 返回：\(preview)"
            lastTrendConnectionMessage = "连通正常：\(result.model) · \(result.endpoint)。\(suffix)"
        } catch {
            trendConnectionState = .failed
            lastTrendConnectionMessage = error.localizedDescription
            lastTrendError = error.localizedDescription
        }
    }

    func generateTrendAnalysis(userInitiated: Bool, createdAt: String? = nil) async {
        guard trendSettings.provider.isConfigured else {
            trendGenerationState = .failed
            lastTrendError = "趋势分析模型配置不完整。"
            return
        }

        let generatedAt = createdAt ?? Self.timestampString()
        trendGenerationState = .generating
        lastTrendError = ""
        trendProgressLogs = []
        appendTrendProgress("开始趋势分析：\(trendSettings.provider.model)")
        appendTrendProgress("准备参数：\(trendPrivacyMode.rawValue) · \(trendSettings.provider.supportsOnlineSearch ? "允许外部信号" : "仅本地上下文") · 超时 \(trendTimeoutText(trendSettings.provider))")
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

        do {
            let report = try await generateTrendReport(context: context, settings: trendSettings)
            appendTrendProgress("校验模型报告")
            let validation = TrendAnalysisValidator().validate(report)
            guard validation.isValid else {
                trendGenerationState = .rejected
                lastTrendError = validation.messages.joined(separator: "\n")
                appendTrendProgress("趋势分析被拦截：报告未通过安全校验")
                return
            }

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
        let promptBuilder = TrendPromptBuilder()
        let chunker = TrendAnalysisChunker()
        guard chunker.shouldChunk(context) else {
            appendTrendProgress("单次分析：\(context.assets.count) 个标的")
            appendTrendProgress("生成提示词：单次分析 · \(context.privacyMode.rawValue)")
            let prompt = promptBuilder.build(context: context, settings: settings)
            let report = try await requestTrendReport(
                prompt: prompt,
                settings: settings.provider,
                phase: "单次分析"
            )
            appendTrendProgress("单次分析完成")
            return report
        }

        let chunks = chunker.chunks(from: context)
        appendTrendProgress("分块模式：按板块拆为 \(chunks.count) 个请求")
        var chunkReports: [TrendAnalysisReport] = []
        for (offset, chunkContext) in chunks.enumerated() {
            let sectorText = chunkContext.sectors.map(\.name).joined(separator: "、")
            let targetText = sectorText.isEmpty ? "未分类板块" : sectorText
            appendTrendProgress("分析分块 \(offset + 1)/\(chunks.count)：\(targetText) · \(chunkContext.assets.count) 个标的")
            appendTrendProgress("生成提示词：分块 \(offset + 1)/\(chunks.count) · \(chunkContext.privacyMode.rawValue)")
            let prompt = promptBuilder.buildChunk(
                context: chunkContext,
                chunkIndex: offset + 1,
                chunkCount: chunks.count,
                settings: settings
            )
            let chunkReport = try await requestTrendReport(
                prompt: prompt,
                settings: settings.provider,
                phase: "分块 \(offset + 1)/\(chunks.count)"
            )
            chunkReports.append(chunkReport)
            appendTrendProgress("分块 \(offset + 1)/\(chunks.count) 完成：\(targetText)")
        }

        appendTrendProgress("合成全组合报告")
        appendTrendProgress("生成提示词：合成全组合报告")
        let synthesisPrompt = promptBuilder.buildSynthesis(
            context: chunker.synthesisContext(from: context),
            chunkReports: chunkReports,
            settings: settings
        )
        return try await requestTrendReport(
            prompt: synthesisPrompt,
            settings: settings.provider,
            phase: "合成全组合报告"
        )
    }

    private func requestTrendReport(
        prompt: TrendModelPrompt,
        settings: TrendAIProviderSettings,
        phase: String
    ) async throws -> TrendAnalysisReport {
        appendTrendProgress("发送模型请求：\(phase) · \(settings.model) · 超时 \(trendTimeoutText(settings))")
        let heartbeatTask = startTrendProgressHeartbeat(phase: phase)
        defer { heartbeatTask.cancel() }
        let report = try await trendAIClient.generateReport(prompt: prompt, settings: settings)
        appendTrendProgress("收到模型报告：\(phase)，准备解析与校验")
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

    private func appendTrendProgress(_ message: String) {
        let entry = TrendProgressLog(timestamp: Self.timestampString(), message: message)
        trendProgressLogs.append(entry)
        if trendProgressLogs.count > 50 {
            trendProgressLogs.removeFirst(trendProgressLogs.count - 50)
        }
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
