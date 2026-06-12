import AppKit
import Foundation

extension AppModel {
    var managerWatchTimelineSummary: ManagerWatchTimelineSummary {
        ManagerWatchTimelineSummary.make(events: managerWatchTimelineEvents)
    }

    var portfolioSnapshotInsightSummary: PortfolioSnapshotInsightSummary {
        PortfolioSnapshotInsightSummary.make(
            snapshots: portfolioInsightSnapshots,
            currentRows: personalAssetRows
        )
    }

    func loadEnhancementState() {
        loadMonthlyReportExportMetadata()
        loadManagerWatchTimeline()
        loadImportUndoSnapshot()
        loadPortfolioInsightSnapshots()
    }

    func loadMonthlyReportExportMetadata() {
        guard let monthlyReportExportMetadataURL else { return }
        do {
            lastMonthlyReportExport = try MonthlyReportExportMetadataStore().load(from: monthlyReportExportMetadataURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadManagerWatchTimeline() {
        guard let managerWatchTimelineFileURL else { return }
        do {
            managerWatchTimelineEvents = try ManagerWatchTimelineStore().load(from: managerWatchTimelineFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadImportUndoSnapshot() {
        guard let importUndoSnapshotFileURL else { return }
        do {
            importUndoSnapshot = try ImportUndoSnapshotStore().load(from: importUndoSnapshotFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPortfolioInsightSnapshots() {
        guard let portfolioInsightSnapshotsFileURL else { return }
        do {
            portfolioInsightSnapshots = try PortfolioSnapshotInsightStore().load(from: portfolioInsightSnapshotsFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyMonthlyReportToPasteboard(_ report: MonthlyReportSummary) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report.markdown, forType: .string)
        noticeMessage = "已复制月报 Markdown。"
    }

    func archiveMonthlyReport(overwriteConfirmed: Bool = false) {
        guard let dataDirectoryURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法导出月报。"
            return
        }

        do {
            let metadata = try MonthlyReportExporter().archive(
                report: monthlyReportSummary,
                in: dataDirectoryURL,
                exportedAt: Self.timestampString(),
                overwriteConfirmed: overwriteConfirmed
            )
            try persistMonthlyReportExportMetadata(metadata)
            pendingOverwriteReportURL = nil
            noticeMessage = "已导出月报：\(URL(fileURLWithPath: metadata.filePath).lastPathComponent)"
        } catch MonthlyReportExportError.archiveAlreadyExists(let url) {
            pendingOverwriteReportURL = url
            errorMessage = "月报已存在，确认覆盖后可重新导出：\(url.lastPathComponent)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveMonthlyReportAs(to url: URL) {
        do {
            let metadata = try MonthlyReportExporter().saveAs(
                report: monthlyReportSummary,
                to: url,
                exportedAt: Self.timestampString()
            )
            try persistMonthlyReportExportMetadata(metadata)
            noticeMessage = "已另存月报：\(url.lastPathComponent)"
        } catch {
            errorMessage = "月报写入失败：\(url.path)；\(error.localizedDescription)"
        }
    }

    func recordManagerWatchTimelineEvent(_ event: ManagerWatchTimelineEvent) {
        guard let managerWatchTimelineFileURL else { return }
        do {
            try ManagerWatchTimelineStore().append(event, to: managerWatchTimelineFileURL)
            managerWatchTimelineEvents = try ManagerWatchTimelineStore().load(from: managerWatchTimelineFileURL)
        } catch {
            managerWatchTimelineEvents = ManagerWatchTimelineStore.pruned(managerWatchTimelineEvents + [event])
        }
    }

    func recordPortfolioInsightSnapshotIfPossible(createdAt: String? = nil) {
        guard let portfolioInsightSnapshotsFileURL, !personalAssetRows.isEmpty else { return }
        let snapshot = PortfolioInsightSnapshot.make(rows: personalAssetRows, createdAt: createdAt ?? Self.timestampString())
        do {
            try PortfolioSnapshotInsightStore().append(snapshot, to: portfolioInsightSnapshotsFileURL)
            portfolioInsightSnapshots = try PortfolioSnapshotInsightStore().load(from: portfolioInsightSnapshotsFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistMonthlyReportExportMetadata(_ metadata: MonthlyReportExportMetadata) throws {
        guard let monthlyReportExportMetadataURL else { return }
        try MonthlyReportExportMetadataStore().save(metadata, to: monthlyReportExportMetadataURL)
        lastMonthlyReportExport = metadata
    }
}
