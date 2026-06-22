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

    func generateTrendAnalysis(userInitiated: Bool, createdAt: String? = nil) async {
        guard trendSettings.provider.isConfigured else {
            trendGenerationState = .failed
            lastTrendError = "趋势分析模型配置不完整。"
            return
        }

        let generatedAt = createdAt ?? Self.timestampString()
        trendGenerationState = .generating
        lastTrendError = ""
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
        let prompt = TrendPromptBuilder().build(context: context, settings: trendSettings)

        do {
            let report = try await trendAIClient.generateReport(prompt: prompt, settings: trendSettings.provider)
            let validation = TrendAnalysisValidator().validate(report)
            guard validation.isValid else {
                trendGenerationState = .rejected
                lastTrendError = validation.messages.joined(separator: "\n")
                return
            }

            trendReport = report
            lastTrendGeneratedAt = report.generatedAt
            trendGenerationState = .succeeded
            if !userInitiated {
                trendSettings.lastAutoAnalysisDay = trendDayString(from: generatedAt)
            }
            saveTrendAnalysisReport(report)
            saveTrendAnalysisSettings()
        } catch {
            trendGenerationState = .failed
            lastTrendError = error.localizedDescription
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
}
