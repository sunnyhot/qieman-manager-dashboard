import Foundation

extension AppModel {
    var enhancementTrendStatus: EnhancementTrendStatus {
        let generatedAt = lastTrendGeneratedAt ?? trendReport?.generatedAt
        let currentDay = trendDayString(from: Self.timestampString())
        let generatedDay = generatedAt.map { trendDayString(from: $0) }
        let stale = generatedDay.map { $0 != currentDay } ?? false
        let isAgentConfigured = trendSettings.agent.isRunnable(with: trendAgentCandidates)
        let headline: String
        if let report = trendReport {
            headline = report.portfolio.headline
        } else if !lastTrendError.isEmpty {
            headline = lastTrendError
        } else {
            headline = isAgentConfigured ? "等待生成趋势分析" : "尚未配置趋势分析 Agent"
        }

        return EnhancementTrendStatus(
            isProviderConfigured: isAgentConfigured,
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

        detectTrendAgents()
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

    func detectTrendAgents() {
        trendAgentCandidates = trendAgentDetector.detect()
    }

    func checkTrendAgentConnection() async {
        guard trendSettings.agent.isRunnable(with: trendAgentCandidates) else {
            trendConnectionState = .failed
            lastTrendConnectionMessage = TrendAgentRunnerError.noRunnableAgent.localizedDescription
            return
        }

        trendConnectionState = .checking
        lastTrendConnectionMessage = "正在检测 \(trendSettings.agent.kind.displayName)..."
        lastTrendError = ""

        do {
            let result = try await trendAgentRunner.check(
                settings: trendSettings.agent,
                candidates: trendAgentCandidates
            )
            trendConnectionState = .succeeded
            let preview = result.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = preview.isEmpty ? "" : " 返回：\(preview)"
            lastTrendConnectionMessage = "Agent 可用：\(result.agentName) · \(result.commandPath)。\(suffix)"
        } catch {
            trendConnectionState = .failed
            lastTrendConnectionMessage = error.localizedDescription
            lastTrendError = error.localizedDescription
        }
    }

    func generateTrendAnalysis(userInitiated: Bool, createdAt: String? = nil) async {
        guard trendSettings.agent.isRunnable(with: trendAgentCandidates) else {
            trendGenerationState = .failed
            lastTrendError = TrendAgentRunnerError.noRunnableAgent.localizedDescription
            return
        }

        let generatedAt = createdAt ?? Self.timestampString()
        trendGenerationState = .generating
        lastTrendError = ""
        trendProgressLogs = []
        appendTrendProgress("开始趋势分析：\(trendSettings.agent.kind.displayName)")
        appendTrendProgress("准备参数：\(trendPrivacyMode.rawValue) · 本地 Agent · 超时 \(trendTimeoutText(trendSettings.agent))")
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
        guard trendSettings.agent.isRunnable(with: trendAgentCandidates) else { return }

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
        appendTrendProgress("单次 Agent 分析：\(context.assets.count) 个标的，\(context.sectors.count) 个板块")
        appendTrendProgress("生成提示词与运行数据包：\(context.privacyMode.rawValue)")
        return try await requestTrendReport(
            context: context,
            settings: settings,
            phase: "本地 Agent 分析"
        )
    }

    private func requestTrendReport(
        context: TrendAnalysisContext,
        settings: TrendAnalysisSettings,
        phase: String
    ) async throws -> TrendAnalysisReport {
        let prompt = TrendPromptBuilder().build(context: context, settings: settings)
        let workspace = TrendRunWorkspace(
            rootDirectory: trendRunRootURL(),
            skillRoot: try trendSkillRootURL()
        )
        let packet = try workspace.prepare(context: context, prompt: prompt)
        appendTrendProgress("启动本地 Agent：\(settings.agent.kind.displayName) · 超时 \(trendTimeoutText(settings.agent))")
        let heartbeatTask = startTrendProgressHeartbeat(phase: phase)
        defer { heartbeatTask.cancel() }
        let result = try await trendAgentRunner.generateReport(
            packet: packet,
            settings: settings.agent,
            candidates: trendAgentCandidates
        )
        appendTrendProgress("收到 Agent 报告：\(result.agentName) · \(String(format: "%.1f", result.durationSeconds))s")
        return try decodeTrendReportJSON(result.reportJSON)
    }

    private func startTrendProgressHeartbeat(phase: String) -> Task<Void, Never> {
        let interval = trendProgressHeartbeatIntervalNanoseconds
        guard interval > 0 else { return Task {} }
        return Task { [weak self] in
            var elapsed = interval
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                self?.appendTrendProgress("等待 Agent 返回：\(phase) 已等待 \(Self.trendElapsedText(elapsed))")
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

    private func trendTimeoutText(_ settings: TrendAgentSettings) -> String {
        "\(Int(settings.timeoutSeconds.rounded())) 秒"
    }

    private func decodeTrendReportJSON(_ json: String) throws -> TrendAnalysisReport {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(TrendAnalysisReport.self, from: data)
    }

    private func trendRunRootURL() -> URL {
        let base = dataDirectoryURL ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("trend-runs", isDirectory: true)
    }

    private func trendSkillRootURL() throws -> URL {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let candidates: [URL?] = [
            env["QIEMAN_PROJECT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("skills/investment-trend-analysis", isDirectory: true) },
            Bundle.main.resourceURL?.appendingPathComponent("project/skills/investment-trend-analysis", isDirectory: true),
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true).appendingPathComponent("skills/investment-trend-analysis", isDirectory: true),
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true).deletingLastPathComponent().appendingPathComponent("skills/investment-trend-analysis", isDirectory: true)
        ]
        for candidate in candidates.compactMap({ $0 }) {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("SKILL.md").path) {
                return candidate
            }
        }
        throw TrendAgentRunnerError.commandFailed("趋势分析 skill 缺失：skills/investment-trend-analysis")
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
