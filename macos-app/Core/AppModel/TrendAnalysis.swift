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
        trendSettings.normalizeDailyAutoAnalysisTimes()
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

    // MARK: - 连通性与能力检测

    /// 检测模型是否支持原生工具调用（内嵌 Agent 的硬性前提）。
    func checkTrendAIConnection() async {
        guard trendSettings.provider.isConfigured else {
            trendConnectionState = .failed
            trendProviderCapabilities = nil
            lastTrendConnectionMessage = OpenAICompatibleAgentClientError.missingConfiguration.localizedDescription
            lastTrendError = lastTrendConnectionMessage
            return
        }

        saveTrendAnalysisSettings()
        trendConnectionState = .checking
        lastTrendConnectionMessage = "正在检测 \(trendSettings.provider.model) 的工具调用能力..."
        lastTrendError = ""

        do {
            let capabilities = try await trendCapabilityProbe(trendSettings.provider)
            trendProviderCapabilities = capabilities
            if capabilities.supportsToolCalls {
                trendConnectionState = .succeeded
                let forced = capabilities.supportsForcedToolChoice ? "（支持指定函数 tool_choice）" : "（仅 auto 工具调用）"
                lastTrendConnectionMessage = "模型可用，支持工具调用：\(trendSettings.provider.model)\(forced)。"
            } else {
                trendConnectionState = .failed
                lastTrendConnectionMessage = "该模型仅返回普通文本，不支持工具调用，无法启动内嵌趋势 Agent。\(capabilities.detail)"
                lastTrendError = lastTrendConnectionMessage
            }
        } catch {
            trendConnectionState = .failed
            trendProviderCapabilities = nil
            lastTrendConnectionMessage = error.localizedDescription
            lastTrendError = error.localizedDescription
        }
    }

    // MARK: - 趋势分析主入口（内嵌 Agent）

    func generateTrendAnalysis(userInitiated: Bool, createdAt: String? = nil) async {
        guard trendSettings.provider.isConfigured else {
            trendGenerationState = .failed
            lastTrendError = OpenAICompatibleAgentClientError.missingConfiguration.localizedDescription
            return
        }
        let generatedAt = createdAt ?? Self.timestampString()
        let autoAnalysisSlot = userInitiated ? nil : trendSettings.dueAutoAnalysisSlot(at: generatedAt)
        let provider = trendSettings.provider.upgradedForTrendGeneration
        trendGenerationState = .generating
        lastTrendError = ""
        trendProgressLogs = []
        trendSettings.defaultPrivacyMode = trendPrivacyMode

        // 能力检测 fail-closed：仅当「当前 Provider 指纹对应 supportsToolCalls==true」才启动；
        // 指纹不符（首次或改了 Base URL/模型/Key）或尚无结果时，先自动探测一次。
        if trendProviderCapabilities?.providerFingerprint != provider.fingerprint
            || trendProviderCapabilities?.supportsToolCalls != true {
            appendTrendProgress("检测 \(provider.model) 的工具调用能力...")
            do {
                let capabilities = try await trendCapabilityProbe(provider)
                trendProviderCapabilities = capabilities
                guard capabilities.supportsToolCalls else {
                    trendGenerationState = .failed
                    lastTrendError = "该模型不支持工具调用，无法启动趋势 Agent。\(capabilities.detail)"
                    appendTrendProgress("趋势分析失败：\(lastTrendError)")
                    return
                }
            } catch {
                trendGenerationState = .failed
                lastTrendError = "工具调用能力检测失败：\(error.localizedDescription)"
                appendTrendProgress("趋势分析失败：\(lastTrendError)")
                return
            }
        }

        appendTrendProgress("开始内嵌趋势 Agent：\(provider.model)")

        let snapshot = makeTrendResearchSnapshot(generatedAt: generatedAt)
        let searchText = trendSettings.webSearch.isConfigured ? "Tavily 联网搜索已配置" : "未配置联网搜索"
        appendTrendProgress("冻结分析快照：\(snapshot.assets.count) 个标的、\(snapshot.marketQuotes.count) 条行情、\(searchText)、隐私 \(snapshot.privacyMode.rawValue)")

        appendTrendProgress("启动模型：\(provider.model) · 单次超时 \(trendTimeoutText(provider))")

        do {
            let report = try await trendResearchAgent.run(
                snapshot: snapshot,
                settings: provider,
                webSearchSettings: trendSettings.webSearch,
                eventHandler: { [weak self] event in
                    Task { @MainActor in self?.handleTrendAgentEvent(event) }
                }
            )
            trendReport = report
            lastTrendGeneratedAt = report.generatedAt
            trendGenerationState = .succeeded
            if !userInitiated {
                trendSettings.lastAutoAnalysisDay = trendDayString(from: generatedAt)
                trendSettings.lastAutoAnalysisSlotKey = autoAnalysisSlot?.key
            }
            appendTrendProgress("保存趋势报告")
            saveTrendAnalysisReport(report)
            saveTrendAnalysisSettings()
            appendTrendProgress("趋势分析完成")
        } catch is CancellationError {
            trendGenerationState = .failed
            lastTrendError = "趋势分析已取消。"
            appendTrendProgress("趋势分析已取消，保留上一次报告")
        } catch {
            trendGenerationState = .failed
            lastTrendError = error.localizedDescription
            appendTrendProgress("趋势分析失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 生成任务管理（支持取消）

    /// 由 UI 触发：取消上一次（若有）并启动新的趋势分析任务。
    func startTrendAnalysis(userInitiated: Bool) {
        trendGenerationTask?.cancel()
        trendGenerationTask = Task { [weak self] in
            await self?.generateTrendAnalysis(userInitiated: userInitiated, createdAt: nil)
            self?.trendGenerationTask = nil
        }
    }

    /// 取消正在进行的趋势分析；Agent 循环会在下一个取消点停止，并保留上一次报告。
    func cancelTrendAnalysis() {
        trendGenerationTask?.cancel()
    }

    func runDailyTrendAnalysisIfNeeded(createdAt: String? = nil) async {
        guard trendSettings.dailyAutoAnalysisEnabled else { return }
        guard trendSettings.provider.isConfigured else { return }
        guard trendGenerationState != .generating else { return }

        let generatedAt = createdAt ?? Self.timestampString()
        trendSettings.normalizeDailyAutoAnalysisTimes()
        guard trendSettings.dueAutoAnalysisSlot(at: generatedAt) != nil else { return }

        await generateTrendAnalysis(userInitiated: false, createdAt: generatedAt)
    }

    // MARK: - 快照组装

    private func makeTrendResearchSnapshot(generatedAt: String) -> TrendResearchSnapshot {
        var sourceWarnings: [String] = []
        if marketIndexQuotes.isEmpty { sourceWarnings.append("当前无大盘指数行情（菜单栏行情可能未开启）。") }
        if !trendSettings.webSearch.isConfigured { sourceWarnings.append("未配置 Tavily API Key，本次无法检索最新行业和政策信息。") }
        sourceWarnings.append("部分底层来源未提供精确截止时间，dataAsOf 取快照创建时间。")

        return TrendResearchSnapshotBuilder().build(
            rows: personalAssetRows,
            summary: personalAssetSummary,
            platformPayload: nil,
            alfaPayload: nil,
            managerWatchEvents: [],
            marketIndexQuotes: marketIndexQuotes,
            fundEstimates: makeTrendResearchFundEstimates(),
            watchSummary: managerWatchTimelineSummary,
            insightSummary: portfolioSnapshotInsightSummary,
            privacyMode: trendPrivacyMode,
            runID: UUID(),
            createdAt: generatedAt,
            dataAsOf: generatedAt,
            sourceWarnings: sourceWarnings
        )
    }

    /// 从个人持仓估值行组装基金估值（已持有基金的最可靠来源）。非持有标的不纳入。
    private func makeTrendResearchFundEstimates() -> [String: TrendResearchFundEstimate] {
        var estimates: [String: TrendResearchFundEstimate] = [:]
        for row in personalAssetRows {
            guard let code = row.fundCode, !code.isEmpty, estimates[code] == nil else { continue }
            estimates[code] = TrendResearchFundEstimate(
                code: code,
                name: row.fundName,
                estimateChangePct: row.estimateChangePct,
                price: row.currentPrice,
                quotedAt: nil,
                sourceLabel: "本地持仓估值"
            )
        }
        return estimates
    }

    // MARK: - Agent 事件 → 进度日志

    @MainActor
    private func handleTrendAgentEvent(_ event: TrendResearchAgentEvent) {
        switch event {
        case .started:
            appendTrendProgress("内嵌趋势 Agent 已启动")
        case .turnStarted(let turn):
            appendTrendProgress("第 \(turn) 轮")
        case .modelRequestStarted:
            appendTrendProgress("请求模型")
        case .modelResponseReceived(_, let duration):
            appendTrendProgress("收到模型响应（\(String(format: "%.1f", duration))s）")
        case .toolStarted(let name):
            appendTrendProgress("调用工具：\(name)")
        case .toolFinished(let name, let summary):
            appendTrendProgress("工具完成：\(name)（\(summary)）")
        case .reportValidationFailed(let errors, let remaining):
            appendTrendProgress("报告校验失败，自动修正（剩余 \(remaining) 次）", detail: errors.joined(separator: "\n"))
        case .completed(let duration):
            appendTrendProgress("Agent 完成（\(String(format: "%.1f", duration))s）")
        case .failed(let message):
            appendTrendProgress("Agent 失败：\(message)")
        case .cancelled:
            appendTrendProgress("Agent 取消")
        }
    }

    // MARK: - 进度与工具方法

    private func trendDayString(from timestamp: String) -> String {
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return trimmed }
        return String(trimmed.prefix(10))
    }

    private func appendTrendProgress(_ message: String, detail: String? = nil) {
        let entry = TrendProgressLog(timestamp: Self.timestampString(), message: message, detail: detail)
        trendProgressLogs.append(entry)
        if trendProgressLogs.count > 50 {
            trendProgressLogs.removeFirst(trendProgressLogs.count - 50)
        }
    }

    private func trendTimeoutText(_ settings: TrendAIProviderSettings) -> String {
        "\(Int(settings.timeoutSeconds.rounded())) 秒"
    }
}
