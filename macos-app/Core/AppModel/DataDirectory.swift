import AppKit
import Foundation

extension AppModel {
    static let customDataDirectoryKey = "qieman.dashboard.customDataDirectory"

    func changeDataDirectory(to newURL: URL) {
        let fm = FileManager.default
        let oldURL = dataDirectoryURL

        do {
            try fm.createDirectory(at: newURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: newURL.appendingPathComponent("output", isDirectory: true), withIntermediateDirectories: true)

            if let oldURL {
                migrateDataFiles(from: oldURL, to: newURL)
            }

            UserDefaults.standard.set(newURL.path, forKey: Self.customDataDirectoryKey)

            dataDirectoryURL = newURL
            logFileURL = newURL.appendingPathComponent("dashboard.log", isDirectory: false)
            dataController.updateSupportDirectory(newURL)

            loadSavedPortfolio()
            loadPendingTrades()
            loadInvestmentPlans()
            loadManagerWatchSettings()
            loadEnhancementState()

            noticeMessage = "数据存储目录已更新。"
        } catch {
            errorMessage = "切换存储目录失败：\(error.localizedDescription)"
        }
    }

    func resetDataDirectory() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let defaultURL = appSupport.appendingPathComponent("QiemanDashboard", isDirectory: true)

        if let currentURL = dataDirectoryURL, currentURL.path != defaultURL.path {
            migrateDataFiles(from: currentURL, to: defaultURL)
        }

        UserDefaults.standard.removeObject(forKey: Self.customDataDirectoryKey)

        do {
            try fm.createDirectory(at: defaultURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: defaultURL.appendingPathComponent("output", isDirectory: true), withIntermediateDirectories: true)
        } catch {
            errorMessage = "恢复默认目录失败：\(error.localizedDescription)"
            return
        }

        dataDirectoryURL = defaultURL
        logFileURL = defaultURL.appendingPathComponent("dashboard.log", isDirectory: false)
        dataController.updateSupportDirectory(defaultURL)

        loadSavedPortfolio()
        loadPendingTrades()
        loadInvestmentPlans()
        loadManagerWatchSettings()
        loadEnhancementState()

        noticeMessage = "数据存储目录已恢复为默认位置。"
    }

    func openDataDirectoryInFinder() {
        guard let url = dataDirectoryURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func migrateDataFiles(from source: URL, to destination: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }

        for item in contents {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: destItem.path) { continue }
            try? fm.copyItem(at: item, to: destItem)
        }
    }
}
