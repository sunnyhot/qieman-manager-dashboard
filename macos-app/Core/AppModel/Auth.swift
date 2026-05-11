import AppKit
import Foundation
import ServiceManagement

// MARK: - Auth, Comments & Login

extension AppModel {
    func validateAuth() async {
        isCheckingAuth = true
        errorMessage = ""
        defer { isCheckingAuth = false }

        let payload = await nativeClient.validateAuth()
        authPayload = payload
        noticeMessage = payload.ok ? "登录态有效：\(payload.userName.isEmpty ? "未知用户" : payload.userName)" : payload.message
    }

    func loadCommentsForSelectedPost() async {
        guard let post = selectedPost, let postID = post.postId else { return }
        let sortType = commentSortType
        let managerBrokerUserID = onlyManagerReplies ? (post.brokerUserId ?? "") : ""
        let requestKey = [
            String(postID),
            sortType,
            managerBrokerUserID
        ].joined(separator: "|")

        activeCommentsRequestKey = requestKey
        commentsPayload = nil
        isLoadingComments = true
        errorMessage = ""
        defer {
            if activeCommentsRequestKey == requestKey {
                isLoadingComments = false
            }
        }

        do {
            let payload = try await nativeClient.fetchComments(
                postID: postID,
                sortType: sortType,
                pageNum: 1,
                pageSize: 10,
                managerBrokerUserID: managerBrokerUserID
            )
            guard activeCommentsRequestKey == requestKey else { return }
            commentsPayload = payload
        } catch {
            guard activeCommentsRequestKey == requestKey else { return }
            errorMessage = error.localizedDescription
        }
    }

    func openDataDirectory() {
        serverController.openDataDirectory()
    }

    func presentLoginSheet() {
        do {
            let supportDirectory = try serverController.prepareEnvironment()
            dataDirectoryURL = supportDirectory
            logFileURL = serverController.logFileURL
            rebuildNativeStatus()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isPresentingLoginSheet = true
    }

    func handleCookieSavedFromLoginSheet() {
        rebuildNativeStatus()
        noticeMessage = "已自动保存登录态。现在可以直接验证登录态，或切到\u{201c}关注动态\u{201d}刷新。"
        Task { await validateAuth() }
    }
}

// MARK: - App Settings, Window & Status

extension AppModel {
    func selectPlatformAction(_ actionID: String) {
        selectedPlatformActionID = actionID
    }

    func updateLaunchAtLoginEnabled(_ isEnabled: Bool) {
        setLaunchAtLoginEnabled(isEnabled)
    }

    func showMainWindow(section: AppSection) {
        selectedSection = section
        revealMainWindowIfNeeded()
    }

    func refreshDataForSectionIfNeeded(_ section: AppSection) {
        guard !isRefreshing else { return }

        switch section {
        case .overview:
            guard !hasForumPosts || !hasPlatformActions else { return }
        case .portfolio:
            guard hasPersonalPortfolio, userPortfolioSnapshot == nil, !isRefreshingPortfolio else { return }
            Task { try? await refreshUserPortfolio(updateNotice: false) }
            return
        case .platform:
            guard !hasPlatformActions else { return }
        case .forum:
            if hasForumPosts {
                ensureSelectedForumPost()
                return
            }
        default:
            return
        }

        if (section == .overview || section == .forum), !form.mode.producesPostRecords {
            form.mode = cookieAvailable ? .followingPosts : .groupManager
        }

        Task { try? await refreshLatest(persist: false, updateNotice: false) }
    }

    func ensureSelectedForumPost(preferredID: String? = nil) {
        guard currentSnapshot?.snapshotType == "posts" else {
            selectedPostID = nil
            return
        }
        let records = currentSnapshot?.records ?? []
        guard !records.isEmpty else {
            selectedPostID = nil
            return
        }
        if let preferredID, records.contains(where: { $0.id == preferredID }) {
            selectedPostID = preferredID
            return
        }
        if let selectedPostID, records.contains(where: { $0.id == selectedPostID }) {
            return
        }
        selectedPostID = records.first?.id
    }

    func ensureSelectedPlatformAction(preferredID: String? = nil) {
        let actions = platformPayload?.actions ?? []
        guard !actions.isEmpty else {
            selectedPlatformActionID = nil
            return
        }
        if let preferredID, actions.contains(where: { $0.id == preferredID }) {
            selectedPlatformActionID = preferredID
            return
        }
        if let selectedPlatformActionID, actions.contains(where: { $0.id == selectedPlatformActionID }) {
            return
        }
        selectedPlatformActionID = actions.first?.id
    }

    func rebuildNativeStatus() {
        let defaultForm = DefaultFormPayload(
            mode: nativeCookieExists ? QueryMode.followingPosts.rawValue : QueryMode.groupManager.rawValue,
            prodCode: "LONG_WIN",
            userName: "ETF拯救世界",
            pages: "5",
            pageSize: "10"
        )

        status = StatusPayload(
            cookieExists: nativeCookieExists,
            cookieFile: serverController.cookieFileURL?.path ?? "",
            outputDir: outputDirectoryURL?.path ?? "",
            defaultForm: defaultForm
        )
    }

    var nativeCookieExists: Bool {
        guard let cookieURL = serverController.cookieFileURL else { return false }
        return FileManager.default.fileExists(atPath: cookieURL.path)
    }

    var managerWatchFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("manager-watch-settings.json", isDirectory: false)
    }

    var preferredManagerWatchName: String {
        let primary = form.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty {
            return primary
        }
        let secondary = form.managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return secondary.isEmpty ? "ETF拯救世界" : secondary
    }

    func refreshLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLoginEnabled = false
        }
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if isEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                refreshLaunchAtLoginStatus()
                noticeMessage = isEnabled ? "已开启开机自启。" : "已关闭开机自启。"
            } catch {
                refreshLaunchAtLoginStatus()
                errorMessage = "设置开机自启失败：\(error.localizedDescription)"
            }
        } else {
            launchAtLoginEnabled = false
            errorMessage = "当前系统版本不支持开机自启设置。"
        }
    }

    func revealMainWindowIfNeeded() {
        appDelegate?.closePopover()
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        appDelegate?.createMainWindow()

        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
