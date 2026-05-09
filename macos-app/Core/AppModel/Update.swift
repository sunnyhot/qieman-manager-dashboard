import AppKit
import Darwin
import Foundation

// MARK: - App Update Management

extension AppModel {
    func checkForUpdates(userInitiated: Bool) async {
        guard !isCheckingForUpdates else { return }
        if userInitiated {
            errorMessage = ""
        } else {
            UserDefaults.standard.set(Date(), forKey: updateAutoCheckDefaultsKey)
        }

        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            let checker = try AppUpdateChecker()
            let update = try await checker.check()
            if let update {
                availableUpdate = update
                isPresentingUpdateSheet = true
                noticeMessage = "发现新版本 \(update.version)，可以下载并重启安装。"
            } else if userInitiated {
                noticeMessage = "已经是最新版本：\(checker.currentVersion)。"
            }
        } catch {
            if userInitiated {
                errorMessage = error.localizedDescription
            }
        }
    }

    func downloadAndInstallAvailableUpdate() async {
        guard let update = availableUpdate else { return }
        guard !isInstallingUpdate else { return }

        isInstallingUpdate = true
        errorMessage = ""
        updateInstallProgress = "正在准备更新…"
        defer {
            isInstallingUpdate = false
        }

        do {
            try await AppSelfUpdater.downloadAndPrepareInstall(release: update) { [weak self] message in
                self?.updateInstallProgress = message
            }
            updateInstallProgress = "安装器已启动，应用即将重启…"
            noticeMessage = "更新包已准备好，正在重启应用完成覆盖安装。"
            try? await Task.sleep(nanoseconds: 600_000_000)
            NSApplication.shared.terminate(nil)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            Darwin.exit(0)
        } catch {
            updateInstallProgress = ""
            errorMessage = error.localizedDescription
        }
    }

    func openAvailableUpdateDownload() {
        guard let url = availableUpdate?.downloadURL else { return }
        NSWorkspace.shared.open(url)
        noticeMessage = "已打开 GitHub 更新下载页。"
    }

    func openAvailableUpdateReleasePage() {
        guard let url = availableUpdate?.htmlURL else { return }
        NSWorkspace.shared.open(url)
        noticeMessage = "已打开 GitHub Release 页面。"
    }

    func dismissUpdateSheet() {
        isPresentingUpdateSheet = false
    }

    func scheduleAutomaticUpdateCheckIfNeeded() {
        let lastCheckDate = UserDefaults.standard.object(forKey: updateAutoCheckDefaultsKey) as? Date
        if let lastCheckDate, Date().timeIntervalSince(lastCheckDate) < updateAutoCheckInterval {
            return
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.checkForUpdates(userInitiated: false)
        }
    }
}
