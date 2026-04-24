import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement

extension Notification.Name {
    static let qiemanNotificationDeepLink = Notification.Name("qieman.notificationDeepLink")
}

private struct LiveRefreshError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .overview
    @Published var form = QueryFormState()

    @Published var status: StatusPayload?
    @Published var history: [SnapshotPayload] = []
    @Published var currentSnapshot: SnapshotPayload?
    @Published var platformPayload: PlatformPayload?
    @Published var authPayload: AuthCheckPayload?
    @Published var commentsPayload: CommentsPayload?
    @Published var portfolioDraft = ""
    @Published var pendingTradesDraft = ""
    @Published var investmentPlansDraft = ""
    @Published var userPortfolioHoldings: [UserPortfolioHolding] = []
    @Published var userPortfolioSnapshot: UserPortfolioSnapshot?
    @Published var pendingTrades: [PersonalPendingTrade] = []
    @Published var investmentPlans: [PersonalInvestmentPlan] = []
    @Published var managerWatchSettings = ManagerWatchSettings.default

    @Published var selectedPostID: String?
    @Published var selectedPlatformActionID: String?
    @Published var commentSortType = "hot"
    @Published var onlyManagerReplies = false
    @Published var launchAtLoginEnabled = false

    @Published var isBootstrapping = false
    @Published var isRefreshing = false
    @Published var isCheckingAuth = false
    @Published var isLoadingComments = false
    @Published var isPresentingLoginSheet = false
    @Published var showAdvancedParams = false
    @Published var isRefreshingPortfolio = false
    @Published var isProcessingImport = false
    @Published var isResolvingPortfolioNames = false
    @Published var isCheckingForUpdates = false
    @Published var availableUpdate: AppUpdateRelease?
    @Published var isPresentingUpdateSheet = false
    @Published var isInstallingUpdate = false
    @Published var updateInstallProgress = ""

    @Published var noticeMessage = ""
    @Published var errorMessage = ""

    @Published private(set) var baseURL: URL?
    @Published private(set) var logFileURL: URL?
    @Published private(set) var dataDirectoryURL: URL?

    private let serverController = LocalServerController()
    private let snapshotStore = NativeSnapshotStore()
    private let platformClient = QiemanPlatformNativeClient()
    private let portfolioStore = UserPortfolioStore()
    private let pendingTradesStore = PendingTradesStore()
    private let investmentPlansStore = InvestmentPlansStore()
    private let managerWatchStore = ManagerWatchStore()
    private let importRecognizer = PersonalImportRecognizer()
    private let notificationManager = LocalNotificationManager()
    private let personalAssetAutomation = PersonalAssetAutomation()
    private let updateAutoCheckDefaultsKey = "qieman.dashboard.update.lastAutoCheckAt"
    private let updateAutoCheckInterval: TimeInterval = 12 * 60 * 60

    private var didApplyDefaultForm = false
    private var didStart = false
    private var managerWatchTask: Task<Void, Never>?
    private var personalAssetAutomationTask: Task<Void, Never>?
    private var activeCommentsRequestKey = ""
    private var isApplyingPersonalAssetAutomation = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .qiemanNotificationDeepLink)
            .sink { [weak self] note in
                guard let payload = note.object as? NotificationDeepLinkPayload else { return }
                self?.handleNotificationDeepLink(payload)
            }
            .store(in: &cancellables)
        refreshLaunchAtLoginStatus()
    }

    deinit {
        managerWatchTask?.cancel()
        personalAssetAutomationTask?.cancel()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            let supportDirectory = try serverController.prepareEnvironment()
            logFileURL = serverController.logFileURL
            dataDirectoryURL = supportDirectory
            loadLocalSnapshots()
            loadSavedPortfolio()
            loadPendingTrades()
            loadInvestmentPlans()
            loadManagerWatchSettings()
            refreshLaunchAtLoginStatus()
            rebuildNativeStatus()
            if !didApplyDefaultForm, let defaultForm = status?.defaultForm {
                form.apply(defaultForm: defaultForm)
                didApplyDefaultForm = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            try await refreshLatest(persist: false, updateNotice: false)
        } catch {
            if currentSnapshot == nil {
                errorMessage = error.localizedDescription
            } else {
                noticeMessage = "已加载本地快照备份，原生直连暂时不可用。"
            }
        }

        if !userPortfolioHoldings.isEmpty {
            try? await refreshUserPortfolio(updateNotice: false)
        }

        await applyPersonalAssetAutomation(updateNotice: false)
        restartManagerWatchLoop(immediate: false)
        restartPersonalAssetAutomationLoop()
        scheduleAutomaticUpdateCheckIfNeeded()
    }

    func refreshLatest(persist: Bool, updateNotice: Bool = true) async throws {
        isRefreshing = true
        errorMessage = ""
        defer { isRefreshing = false }

        let currentForm = form
        let currentOutputDirectory = outputDirectoryURL

        async let snapshotTask = nativeClient.fetchSnapshot(form: currentForm, persist: persist, outputDirectory: currentOutputDirectory)
        async let platformTask = fetchPlatformIfPossible()

        var refreshedSnapshot: SnapshotPayload?
        var refreshedPlatform: PlatformPayload?
        var failures: [String] = []

        do {
            refreshedSnapshot = try await snapshotTask
        } catch {
            failures.append("论坛发言刷新失败：\(error.localizedDescription)")
        }

        do {
            refreshedPlatform = try await platformTask
        } catch {
            failures.append("平台调仓刷新失败：\(error.localizedDescription)")
        }

        if let snapshot = refreshedSnapshot {
            currentSnapshot = snapshot
            commentsPayload = nil
            if selectedPost == nil {
                selectedPostID = snapshot.records.first?.id
            }
        }

        if let platform = refreshedPlatform {
            platformPayload = platform
            ensureSelectedPlatformAction()
        }

        if persist, refreshedSnapshot != nil {
            loadLocalSnapshots()
        } else {
            rebuildNativeStatus()
        }

        guard refreshedSnapshot != nil || refreshedPlatform != nil else {
            let message = failures.isEmpty ? "原生刷新失败，论坛和平台数据都没有拉到。" : failures.joined(separator: "；")
            errorMessage = message
            throw LiveRefreshError(message: message)
        }

        if failures.isEmpty {
            if updateNotice {
                noticeMessage = persist ? "已原生刷新并保存当前结果。" : "已通过原生抓取刷新到最新结果。"
            }
        } else {
            errorMessage = failures.joined(separator: "；")
            if updateNotice {
                noticeMessage = "已刷新可用数据，但有部分内容拉取失败。"
            }
        }
    }

    func validateAuth() async {
        isCheckingAuth = true
        errorMessage = ""
        defer { isCheckingAuth = false }

        let payload = await nativeClient.validateAuth()
        authPayload = payload
        noticeMessage = payload.ok ? "登录态有效：\(payload.userName.isEmpty ? "未知用户" : payload.userName)" : payload.message
    }

    func loadSnapshot(_ snapshot: SnapshotPayload) async {
        guard let fileName = snapshot.fileName, let outputDirectory = outputDirectoryURL else { return }
        errorMessage = ""
        do {
            let payload = try snapshotStore.loadSnapshot(named: fileName, from: outputDirectory)
            currentSnapshot = payload
            commentsPayload = nil
            selectedSection = .snapshots
            selectedPostID = payload.records.first?.id
            noticeMessage = "已切换到快照：\(payload.displayTitle)"
        } catch {
            errorMessage = error.localizedDescription
        }
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
        noticeMessage = "已自动保存登录态。现在可以直接验证登录态，或切到“关注动态”刷新。"
        Task { await validateAuth() }
    }

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

    func savePortfolioFromDraft() {
        guard let portfolioFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存持仓。"
            return
        }
        do {
            let savedCount: Int
            if shouldUsePortfolioSummaryImport(for: portfolioDraft) {
                let existingHoldings = userPortfolioHoldings
                try runPortfolioSummaryImport(text: portfolioDraft)
                let importedHoldings = try portfolioStore.load(from: portfolioFileURL)
                let mergedHoldings = portfolioStore.merging(importedHoldings, into: existingHoldings)
                userPortfolioHoldings = mergedHoldings
                try portfolioStore.save(mergedHoldings, to: portfolioFileURL)
                portfolioDraft = ""
                savedCount = importedHoldings.count
                noticeMessage = "已通过摘要导入保存 \(importedHoldings.count) 条个人持仓，并保留已有基金和股票配置，正在按代码补全名称。"
            } else {
                let importedHoldings = try portfolioStore.parseDraft(portfolioDraft)
                let mergedHoldings = portfolioStore.merging(importedHoldings, into: userPortfolioHoldings)
                userPortfolioHoldings = mergedHoldings
                try portfolioStore.save(mergedHoldings, to: portfolioFileURL)
                savedCount = importedHoldings.count
                portfolioDraft = ""
                noticeMessage = "已保存 \(importedHoldings.count) 条个人持仓，并保留已有基金和股票配置，正在按代码补全名称。"
            }
            Task {
                let resolvedCount = await resolveAndPersistPortfolioNames()
                try? await refreshUserPortfolio(updateNotice: false)
                if resolvedCount > 0 {
                    noticeMessage = "已保存 \(savedCount) 条个人持仓，并通过代码补全 \(resolvedCount) 个名称。已有配置已保留。"
                } else {
                    noticeMessage = "已保存 \(savedCount) 条个人持仓，已有配置已保留。"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePendingTradesFromDraft() {
        guard pendingTradeFileURL != nil else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存买入中记录。"
            return
        }
        do {
            try runTextImportScript(
                scriptRelativePath: "scripts/import_alipay_pending_trades.py",
                text: pendingTradesDraft
            )
            reloadPendingTradesFromDisk()
            noticeMessage = "已保存买入中记录。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveInvestmentPlansFromDraft() {
        guard investmentPlanFileURL != nil else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存定投计划。"
            return
        }
        do {
            try runTextImportScript(
                scriptRelativePath: "scripts/import_alipay_investment_plans.py",
                text: investmentPlansDraft
            )
            reloadInvestmentPlansFromDisk()
            noticeMessage = "已保存定投计划。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearPortfolio() {
        guard let portfolioFileURL else { return }
        do {
            try portfolioStore.delete(at: portfolioFileURL)
            userPortfolioHoldings = []
            userPortfolioSnapshot = nil
            portfolioDraft = ""
            noticeMessage = "已清空个人持仓。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadPortfolioFromDisk() {
        loadSavedPortfolio()
        if userPortfolioHoldings.isEmpty {
            userPortfolioSnapshot = nil
            noticeMessage = "已从磁盘重载持仓，目前没有已保存内容。"
            Task { await applyPersonalAssetAutomation() }
            return
        }
        noticeMessage = "已从磁盘重载 \(userPortfolioHoldings.count) 条个人持仓。"
        Task {
            try? await refreshUserPortfolio(updateNotice: false)
            await applyPersonalAssetAutomation()
        }
    }

    func reloadPendingTradesFromDisk() {
        loadPendingTrades()
        if pendingTrades.isEmpty {
            noticeMessage = "已从磁盘重载买入中记录，目前没有已保存内容。"
            Task { await applyPersonalAssetAutomation() }
            return
        }
        noticeMessage = "已从磁盘重载 \(pendingTrades.count) 条买入中记录。"
        Task { await applyPersonalAssetAutomation() }
    }

    func reloadInvestmentPlansFromDisk() {
        loadInvestmentPlans()
        if investmentPlans.isEmpty {
            noticeMessage = "已从磁盘重载定投计划，目前没有已保存内容。"
            Task { await applyPersonalAssetAutomation() }
            return
        }
        noticeMessage = "已从磁盘重载 \(investmentPlans.count) 条定投计划。"
        Task { await applyPersonalAssetAutomation() }
    }

    func syncManagerWatchTargetsFromCurrentForm() {
        let prodCode = form.prodCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let managerName = preferredManagerWatchName
        if !prodCode.isEmpty {
            managerWatchSettings.prodCode = prodCode
        }
        if !managerName.isEmpty {
            managerWatchSettings.managerName = managerName
        }
        persistManagerWatchSettings(restartLoop: false)
        noticeMessage = "已把通知巡检目标同步成当前查询参数。"
    }

    func updateManagerWatchEnabled(_ isEnabled: Bool) {
        Task { await setManagerWatchEnabled(isEnabled) }
    }

    func updateManagerWatchInterval(_ intervalMinutes: Int) {
        managerWatchSettings.intervalMinutes = max(5, intervalMinutes)
        persistManagerWatchSettings()
        if managerWatchSettings.isEnabled {
            noticeMessage = "通知巡检频率已调整为 \(managerWatchSettings.intervalLabel)。"
        }
    }

    func updateManagerWatchForumEnabled(_ isEnabled: Bool) {
        managerWatchSettings.watchForum = isEnabled
        persistManagerWatchSettings()
    }

    func updateManagerWatchPlatformEnabled(_ isEnabled: Bool) {
        managerWatchSettings.watchPlatform = isEnabled
        persistManagerWatchSettings()
    }

    func saveManagerWatchConfiguration() {
        persistManagerWatchSettings()
        noticeMessage = "已保存主理人通知巡检设置。"
    }

    func runManagerWatchNow() {
        Task { await performManagerWatchPoll(sendNotifications: true, manual: true) }
    }

    func selectPlatformAction(_ actionID: String) {
        selectedPlatformActionID = actionID
    }

    func updateLaunchAtLoginEnabled(_ isEnabled: Bool) {
        setLaunchAtLoginEnabled(isEnabled)
    }

    func refreshUserPortfolio(updateNotice: Bool = true) async throws {
        guard !userPortfolioHoldings.isEmpty else {
            userPortfolioSnapshot = nil
            return
        }
        isRefreshingPortfolio = true
        defer { isRefreshingPortfolio = false }

        let snapshot = try await platformClient.fetchUserPortfolioSnapshot(holdings: userPortfolioHoldings)
        userPortfolioSnapshot = snapshot
        if updateNotice {
            noticeMessage = "个人持仓估值已刷新。"
        }
    }

    @discardableResult
    private func resolveAndPersistPortfolioNames() async -> Int {
        guard let portfolioFileURL else { return 0 }

        let missingNameHoldings = userPortfolioHoldings.filter {
            !$0.normalizedFundCode.isEmpty && $0.normalizedName == nil
        }
        guard !missingNameHoldings.isEmpty else { return 0 }

        isResolvingPortfolioNames = true
        defer { isResolvingPortfolioNames = false }

        let namesByHoldingID = await platformClient.resolveAssetNames(holdings: missingNameHoldings)
        guard !namesByHoldingID.isEmpty else { return 0 }

        var resolvedCount = 0
        let enrichedHoldings = userPortfolioHoldings.map { holding in
            guard holding.normalizedName == nil,
                  let resolvedName = namesByHoldingID[holding.id],
                  !resolvedName.isEmpty
            else {
                return holding
            }
            resolvedCount += 1
            return UserPortfolioHolding(
                id: holding.id,
                fundCode: holding.fundCode,
                assetType: holding.assetType,
                units: holding.units,
                costPrice: holding.costPrice,
                displayName: resolvedName
            )
        }

        guard resolvedCount > 0 else { return 0 }

        do {
            userPortfolioHoldings = enrichedHoldings
            try portfolioStore.save(enrichedHoldings, to: portfolioFileURL)
            return resolvedCount
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    func draft(for target: PersonalDataImportTarget) -> String {
        switch target {
        case .holdings:
            return portfolioDraft
        case .pendingTrades:
            return pendingTradesDraft
        case .investmentPlans:
            return investmentPlansDraft
        }
    }

    func updateDraft(_ value: String, for target: PersonalDataImportTarget) {
        switch target {
        case .holdings:
            portfolioDraft = value
        case .pendingTrades:
            pendingTradesDraft = value
        case .investmentPlans:
            investmentPlansDraft = value
        }
    }

    func saveDraft(for target: PersonalDataImportTarget) {
        switch target {
        case .holdings:
            savePortfolioFromDraft()
        case .pendingTrades:
            savePendingTradesFromDraft()
        case .investmentPlans:
            saveInvestmentPlansFromDraft()
        }
    }

    func reloadDraftTargetFromDisk(_ target: PersonalDataImportTarget) {
        switch target {
        case .holdings:
            reloadPortfolioFromDisk()
        case .pendingTrades:
            reloadPendingTradesFromDisk()
        case .investmentPlans:
            reloadInvestmentPlansFromDisk()
        }
    }

    func hasImportedData(for target: PersonalDataImportTarget) -> Bool {
        switch target {
        case .holdings:
            return hasPersonalPortfolio
        case .pendingTrades:
            return hasPendingTrades
        case .investmentPlans:
            return hasInvestmentPlans
        }
    }

    func importExternalFile(at fileURL: URL, source: PersonalDataImportSource, target: PersonalDataImportTarget) async {
        isProcessingImport = true
        errorMessage = ""
        defer { isProcessingImport = false }

        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            _ = try serverController.prepareEnvironment()
            guard let projectDirectory = serverController.projectDirectory else {
                throw LocalServerError.projectMissing
            }

            let preparedInputURL: URL
            if source == .image {
                let recognizedText = try await importRecognizer.recognizeText(from: fileURL)
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qieman-image-ocr-\(UUID().uuidString).txt")
                try recognizedText.write(to: tempURL, atomically: true, encoding: .utf8)
                preparedInputURL = tempURL
            } else {
                preparedInputURL = fileURL
            }

            let draft = try runPrepareImportScript(
                projectDirectory: projectDirectory,
                target: target,
                source: source,
                inputURL: preparedInputURL
            )
            updateDraft(draft, for: target)
            noticeMessage = source == .image ? "图片已识别到草稿区，请核对后保存。" : "表格已导入草稿区，请核对后保存。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var selectedPost: SnapshotRecordPayload? {
        currentSnapshot?.records.first(where: { $0.id == selectedPostID }) ?? currentSnapshot?.records.first
    }

    var selectedPlatformAction: PlatformActionPayload? {
        guard let actions = platformPayload?.actions, !actions.isEmpty else { return nil }
        if let selectedPlatformActionID,
           let matched = actions.first(where: { $0.id == selectedPlatformActionID }) {
            return matched
        }
        return actions.first
    }

    var latestPlatformActions: [PlatformActionPayload] {
        Array((platformPayload?.actions ?? []).prefix(8))
    }

    var platformHoldings: [HoldingItemPayload] {
        platformPayload?.holdings?.items ?? []
    }

    var forumRecords: [SnapshotRecordPayload] {
        currentSnapshot?.records ?? []
    }

    var portfolioFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("user-portfolio.json", isDirectory: false)
    }

    var pendingTradeFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("user-pending-trades.json", isDirectory: false)
    }

    var investmentPlanFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("user-investment-plans.json", isDirectory: false)
    }

    var hasLiveService: Bool {
        baseURL != nil
    }

    var cookieAvailable: Bool {
        status?.cookieExists == true || nativeCookieExists
    }

    var canRefreshWithoutLiveService: Bool {
        true
    }

    var liveModeLabel: String {
        if isRefreshing {
            return "刷新中"
        }
        return "原生直连"
    }

    var cookieFileURL: URL? {
        serverController.cookieFileURL
    }

    var currentSnapshotSupportsComments: Bool {
        currentSnapshot?.snapshotType == "posts" && selectedPost?.postId != nil
    }

    var hasPersonalPortfolio: Bool {
        !userPortfolioHoldings.isEmpty
    }

    var hasPendingTrades: Bool {
        !pendingTrades.isEmpty
    }

    var hasInvestmentPlans: Bool {
        !investmentPlans.isEmpty
    }

    var portfolioMenuBarTitle: String {
        if let summary = personalAssetSummary, summary.totalEffectiveHoldingAmount > 0 {
            let total = summary.totalEffectiveHoldingAmount
            if total >= 10_000 {
                return String(format: "%.1f万", total / 10_000)
            }
            return String(format: "%.0f", total)
        }
        if hasPersonalPortfolio {
            return "持仓"
        }
        if hasPendingTrades {
            return "待确认"
        }
        return hasInvestmentPlans ? "计划" : "未配置"
    }

    var managerWatchStatusText: String {
        if managerWatchSettings.isEnabled {
            return "已开启 · \(managerWatchSettings.intervalLabel)"
        }
        return "已关闭"
    }

    var managerWatchScopeText: String {
        let scopes = [
            managerWatchSettings.watchPlatform ? "调仓" : nil,
            managerWatchSettings.watchForum ? "发言" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " + ")
        let scopeText = scopes.isEmpty ? "未选择" : scopes
        return "\(managerWatchSettings.prodCode) · \(managerWatchSettings.managerName) · \(scopeText)"
    }

    var launchAtLoginStatusText: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "已开启"
            case .requiresApproval:
                return "待系统授权"
            case .notFound:
                return "当前构建不支持"
            case .notRegistered:
                return "已关闭"
            @unknown default:
                return "未知"
            }
        }
        return "系统不支持"
    }

    var hasForumPosts: Bool {
        currentSnapshot?.snapshotType == "posts" && !forumRecords.isEmpty
    }

    var hasPlatformActions: Bool {
        !(platformPayload?.actions?.isEmpty ?? true)
    }

    private var nativeClient: QiemanNativeClient {
        QiemanNativeClient(cookieFileURL: serverController.cookieFileURL)
    }

    var monthlyPlatformSummary: [PlatformMonthSummary] {
        let actions = platformPayload?.actions ?? []
        var buckets: [String: (buy: Int, sell: Int, days: Set<String>)] = [:]

        for action in actions {
            let rawDate = action.txnDate ?? action.createdAt ?? ""
            guard rawDate.count >= 10 else { continue }
            let month = String(rawDate.prefix(7))
            let day = String(rawDate.prefix(10))
            var bucket = buckets[month] ?? (0, 0, [])
            if action.side == "buy" {
                bucket.buy += 1
            } else if action.side == "sell" {
                bucket.sell += 1
            }
            bucket.days.insert(day)
            buckets[month] = bucket
        }

        return buckets
            .map { month, bucket in
                PlatformMonthSummary(
                    month: month,
                    totalCount: bucket.buy + bucket.sell,
                    buyCount: bucket.buy,
                    sellCount: bucket.sell,
                    activeDays: bucket.days.count
                )
            }
            .sorted(by: { $0.month > $1.month })
            .prefix(12)
            .map { $0 }
    }

    var pendingTradeSummary: PersonalPendingTradeSummary? {
        guard !pendingTrades.isEmpty else { return nil }
        let totalCashAmount = pendingTrades.compactMap(\.amountValue).reduce(0, +)
        let cashTradeCount = pendingTrades.filter { $0.isCashTrade }.count
        let unitTradeCount = pendingTrades.filter { !$0.isCashTrade }.count
        return PersonalPendingTradeSummary(
            totalCashAmount: totalCashAmount,
            cashTradeCount: cashTradeCount,
            unitTradeCount: unitTradeCount,
            latestTime: pendingTrades.first?.occurredAt,
            actionCount: pendingTrades.count
        )
    }

    var activeInvestmentPlans: [PersonalInvestmentPlan] {
        investmentPlans
            .filter(\.isActivePlan)
            .sorted(by: sortInvestmentPlans)
    }

    var pausedInvestmentPlans: [PersonalInvestmentPlan] {
        investmentPlans
            .filter(\.isPausedPlan)
            .sorted(by: sortInvestmentPlans)
    }

    var endedInvestmentPlans: [PersonalInvestmentPlan] {
        investmentPlans
            .filter(\.isEndedPlan)
            .sorted(by: sortInvestmentPlans)
    }

    var investmentPlanSummary: PersonalInvestmentPlanSummary? {
        guard !investmentPlans.isEmpty else { return nil }
        let activePlans = activeInvestmentPlans
        let pausedPlans = pausedInvestmentPlans
        let endedPlans = endedInvestmentPlans
        let totalCumulativeInvestedAmount = investmentPlans.compactMap(\.cumulativeInvestedAmount).reduce(0, +)
        let smartPlanCount = activePlans.filter(\.isSmartPlan).count
        let dailyPlanCount = activePlans.filter(\.isDailyPlan).count
        let weeklyPlanCount = activePlans.filter(\.isWeeklyPlan).count
        let nextExecutionDate = activePlans
            .map(\.nextExecutionDate)
            .filter { !$0.isEmpty }
            .sorted()
            .first

        return PersonalInvestmentPlanSummary(
            planCount: investmentPlans.count,
            activePlanCount: activePlans.count,
            pausedPlanCount: pausedPlans.count,
            endedPlanCount: endedPlans.count,
            smartPlanCount: smartPlanCount,
            dailyPlanCount: dailyPlanCount,
            weeklyPlanCount: weeklyPlanCount,
            totalCumulativeInvestedAmount: totalCumulativeInvestedAmount,
            nextExecutionDate: nextExecutionDate
        )
    }

    var personalAssetRows: [PersonalAssetAggregateRow] {
        var valuationRowsByKey: [String: UserPortfolioValuationRow] = [:]
        for row in userPortfolioSnapshot?.rows ?? [] {
            valuationRowsByKey[personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName)] = row
        }

        var rawHoldingsByKey: [String: UserPortfolioHolding] = [:]
        for holding in userPortfolioHoldings {
            let key = personalAssetKey(assetType: holding.assetType, code: holding.normalizedFundCode, name: holding.normalizedName)
            rawHoldingsByKey[key] = rawHoldingsByKey[key] ?? holding
        }

        var pendingByKey: [String: [PersonalPendingTrade]] = [:]
        for trade in pendingTrades {
            let key = personalFundKey(code: trade.fundCode, name: trade.fundName)
            pendingByKey[key, default: []].append(trade)
        }

        var plansByKey: [String: [PersonalInvestmentPlan]] = [:]
        for plan in investmentPlans {
            let key = personalFundKey(code: plan.fundCode, name: plan.fundName)
            plansByKey[key, default: []].append(plan)
        }

        let keys = Set(valuationRowsByKey.keys)
            .union(rawHoldingsByKey.keys)
            .union(pendingByKey.keys)
            .union(plansByKey.keys)

        return keys
            .map { key in
                let holdingRow = valuationRowsByKey[key]
                let rawHolding = rawHoldingsByKey[key]
                let pending = (pendingByKey[key] ?? []).sorted { $0.occurredAt > $1.occurredAt }
                let plans = (plansByKey[key] ?? []).sorted(by: sortInvestmentPlans)
                let assetType = holdingRow?.holding.assetType
                    ?? rawHolding?.assetType
                    ?? .fund
                let fundName = holdingRow?.fundName
                    ?? rawHolding?.normalizedName
                    ?? pending.first?.fundName
                    ?? plans.first?.fundName
                    ?? "未命名标的"
                let fundCode = holdingRow?.holding.normalizedFundCode
                    ?? rawHolding?.normalizedFundCode
                    ?? pending.first?.fundCode
                    ?? plans.first?.fundCode

                return PersonalAssetAggregateRow(
                    key: key,
                    assetType: assetType,
                    fundName: fundName,
                    fundCode: normalizedCode(fundCode),
                    holdingRow: holdingRow,
                    rawHolding: rawHolding,
                    pendingTrades: pending,
                    plans: plans
                )
            }
            .sorted { left, right in
                let leftExposure = left.effectiveHoldingAmount
                let rightExposure = right.effectiveHoldingAmount
                if abs(leftExposure - rightExposure) > 0.001 {
                    return leftExposure > rightExposure
                }
                if left.pendingTradeCount != right.pendingTradeCount {
                    return left.pendingTradeCount > right.pendingTradeCount
                }
                if left.totalPlanCount != right.totalPlanCount {
                    return left.totalPlanCount > right.totalPlanCount
                }
                return left.fundName.localizedStandardCompare(right.fundName) == .orderedAscending
            }
    }

    var personalAssetSummary: PersonalAssetAggregateSummary? {
        let rows = personalAssetRows
        guard !rows.isEmpty else { return nil }
        return PersonalAssetAggregateSummary(
            fundCount: rows.count,
            holdingFundCount: rows.filter(\.hasHolding).count,
            pendingFundCount: rows.filter(\.hasPending).count,
            activePlanFundCount: rows.filter { $0.activePlanCount > 0 }.count,
            totalMarketValue: rows.compactMap(\.marketValue).reduce(0, +),
            totalPendingCashAmount: rows.map(\.pendingCashAmount).reduce(0, +),
            totalActivePlanCount: rows.map(\.activePlanCount).reduce(0, +),
            totalPausedPlanCount: rows.map(\.pausedPlanCount).reduce(0, +),
            totalEndedPlanCount: rows.map(\.endedPlanCount).reduce(0, +),
            totalCumulativePlanAmount: rows.map(\.totalCumulativePlanAmount).reduce(0, +),
            totalEstimatedNextPlanAmount: rows.map(\.estimatedNextPlanAmount).reduce(0, +),
            totalEffectiveHoldingAmount: rows.map(\.effectiveHoldingAmount).reduce(0, +)
        )
    }

    private func filteredHistory(_ items: [SnapshotPayload]) -> [SnapshotPayload] {
        items.filter { item in
            let fileName = item.fileName ?? ""
            if fileName.hasPrefix("watch-state-") {
                return false
            }
            return true
        }
    }

    private var outputDirectoryURL: URL? {
        dataDirectoryURL?.appendingPathComponent("output", isDirectory: true)
    }

    private func loadLocalSnapshots() {
        guard let outputDirectory = outputDirectoryURL else { return }
        do {
            let localHistory = filteredHistory(try snapshotStore.loadHistory(from: outputDirectory))
            if !localHistory.isEmpty {
                history = localHistory
            }
            if currentSnapshot == nil,
               let preferred = snapshotStore.preferredSnapshot(from: localHistory, preferPosts: true),
               let fileName = preferred.fileName {
                currentSnapshot = try snapshotStore.loadSnapshot(named: fileName, from: outputDirectory)
                selectedPostID = currentSnapshot?.records.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        rebuildNativeStatus()
    }

    private func loadSavedPortfolio() {
        guard let portfolioFileURL else { return }
        do {
            let holdings = try portfolioStore.load(from: portfolioFileURL)
            userPortfolioHoldings = holdings
            portfolioDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPendingTrades() {
        guard let pendingTradeFileURL else { return }
        do {
            pendingTrades = try pendingTradesStore.load(from: pendingTradeFileURL)
                .sorted { $0.occurredAt > $1.occurredAt }
            pendingTradesDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadInvestmentPlans() {
        guard let investmentPlanFileURL else { return }
        do {
            investmentPlans = try investmentPlansStore.load(from: investmentPlanFileURL)
                .sorted(by: sortInvestmentPlans)
            investmentPlansDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restartPersonalAssetAutomationLoop() {
        personalAssetAutomationTask?.cancel()
        personalAssetAutomationTask = Task { [weak self] in
            let interval: UInt64 = 15 * 60 * 1_000_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self?.applyPersonalAssetAutomation()
            }
        }
    }

    @discardableResult
    private func applyPersonalAssetAutomation(updateNotice: Bool = true) async -> Bool {
        guard dataDirectoryURL != nil, !isApplyingPersonalAssetAutomation else { return false }
        isApplyingPersonalAssetAutomation = true
        defer { isApplyingPersonalAssetAutomation = false }

        let today = Date()
        let planResult = personalAssetAutomation.generateDuePlanTrades(
            plans: investmentPlans,
            existingPendingTrades: pendingTrades,
            today: today
        ) { [weak self] plan, _ in
            self?.estimatedAutomationAmount(for: plan)
        }

        let priceByKey = await automationPriceLookup(for: planResult.pendingTrades, holdings: userPortfolioHoldings)
        let confirmationResult = personalAssetAutomation.confirmDuePendingTrades(
            holdings: userPortfolioHoldings,
            pendingTrades: planResult.pendingTrades,
            today: today,
            priceByKey: priceByKey,
            keyForFund: { [weak self] code, name in
                self?.personalFundKey(code: code, name: name) ?? "name:\(name ?? "")"
            }
        )

        var change = planResult.change
        change.confirmedPendingCount += confirmationResult.change.confirmedPendingCount
        change.skippedConfirmationCount += confirmationResult.change.skippedConfirmationCount

        let nextHoldings = confirmationResult.holdings
        let nextPendingTrades = confirmationResult.pendingTrades.sorted { $0.occurredAt > $1.occurredAt }
        let nextInvestmentPlans = planResult.plans.sorted(by: sortInvestmentPlans)

        let holdingsChanged = nextHoldings != userPortfolioHoldings
        let pendingChanged = nextPendingTrades != pendingTrades
        let plansChanged = nextInvestmentPlans != investmentPlans
        guard holdingsChanged || pendingChanged || plansChanged else {
            return false
        }

        do {
            if holdingsChanged, let portfolioFileURL {
                userPortfolioHoldings = nextHoldings
                try portfolioStore.save(nextHoldings, to: portfolioFileURL)
            }
            if pendingChanged, let pendingTradeFileURL {
                pendingTrades = nextPendingTrades
                try pendingTradesStore.save(nextPendingTrades, to: pendingTradeFileURL)
            }
            if plansChanged, let investmentPlanFileURL {
                investmentPlans = nextInvestmentPlans
                try investmentPlansStore.save(nextInvestmentPlans, to: investmentPlanFileURL)
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        if holdingsChanged, !userPortfolioHoldings.isEmpty {
            try? await refreshUserPortfolio(updateNotice: false)
        }
        if updateNotice, let noticeText = change.noticeText {
            noticeMessage = noticeText
        }
        return true
    }

    private func automationPriceLookup(
        for pendingTrades: [PersonalPendingTrade],
        holdings: [UserPortfolioHolding]
    ) async -> [String: Double] {
        var priceByKey: [String: Double] = [:]

        for row in userPortfolioSnapshot?.rows ?? [] {
            let key = personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName)
            if let price = row.resolvedPrice, price > 0 {
                priceByKey[key] = price
            }
        }

        for holding in holdings {
            let key = personalAssetKey(assetType: holding.assetType, code: holding.normalizedFundCode, name: holding.normalizedName)
            if priceByKey[key] == nil, let costPrice = holding.costPrice, costPrice > 0 {
                priceByKey[key] = costPrice
            }
        }

        var syntheticHoldingsByKey: [String: UserPortfolioHolding] = [:]
        for trade in pendingTrades {
            let code = normalizedCode(trade.targetFundCode) ?? normalizedCode(trade.fundCode)
            let name = normalizedText(trade.targetFundName) ?? normalizedText(trade.fundName)
            let key = personalFundKey(code: code, name: name)
            guard priceByKey[key] == nil, let code else { continue }
            syntheticHoldingsByKey[key] = UserPortfolioHolding(
                fundCode: code,
                units: 1,
                costPrice: nil,
                displayName: name
            )
        }

        guard !syntheticHoldingsByKey.isEmpty else {
            return priceByKey
        }

        do {
            let snapshot = try await platformClient.fetchUserPortfolioSnapshot(holdings: Array(syntheticHoldingsByKey.values))
            for row in snapshot.rows {
                let key = personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName)
                if let price = row.resolvedPrice, price > 0 {
                    priceByKey[key] = price
                }
            }
        } catch {
            if errorMessage.isEmpty {
                errorMessage = "部分待确认买入缺少实时价格，暂时保留在待确认。"
            }
        }

        return priceByKey
    }

    private func estimatedAutomationAmount(for plan: PersonalInvestmentPlan) -> Double? {
        let range = automationAmountRange(for: plan)
        guard let low = range.min else { return nil }
        let high = range.max ?? low

        if !plan.isDrawdownMode {
            return abs(high - low) < 0.001 ? low : (low + high) / 2
        }

        guard let changePct = latestEstimateChangePct(for: plan) else {
            return abs(high - low) < 0.001 ? low : (low + high) / 2
        }
        if changePct < 0 {
            return high
        }
        if changePct > 0 {
            return low
        }
        return abs(high - low) < 0.001 ? low : (low + high) / 2
    }

    private func latestEstimateChangePct(for plan: PersonalInvestmentPlan) -> Double? {
        let key = personalFundKey(code: plan.fundCode, name: plan.fundName)
        return userPortfolioSnapshot?.rows.first { row in
            personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName) == key
        }?.estimateChangePct
    }

    private func automationAmountRange(for plan: PersonalInvestmentPlan) -> (min: Double?, max: Double?) {
        let parsed = parsedAutomationAmountRange(from: plan.amountText)
        let minValue = plan.minAmount ?? parsed.min
        let maxValue = plan.maxAmount ?? parsed.max
        switch (minValue, maxValue) {
        case let (min?, max?) where max < min:
            return (max, min)
        case let (min?, max?):
            return (min, max)
        case let (min?, nil):
            return (min, min)
        case let (nil, max?):
            return (max, max)
        default:
            return (nil, nil)
        }
    }

    private func parsedAutomationAmountRange(from text: String) -> (min: Double?, max: Double?) {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = cleaned
            .split { !"0123456789.".contains($0) }
            .compactMap { Double($0) }
        guard let first = numbers.first else {
            return (nil, nil)
        }
        if numbers.count >= 2, let second = numbers.dropFirst().first {
            return (first, second)
        }
        return (first, first)
    }

    private func normalizedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadManagerWatchSettings() {
        guard let managerWatchFileURL else { return }
        do {
            managerWatchSettings = try managerWatchStore.load(from: managerWatchFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shouldUsePortfolioSummaryImport(for text: String) -> Bool {
        text
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed.contains("|")
            }
    }

    private func runPortfolioSummaryImport(text: String) throws {
        try runTextImportScript(
            scriptRelativePath: "scripts/import_alipay_portfolio.py",
            text: text
        )
    }

    private func runTextImportScript(scriptRelativePath: String, text: String) throws {
        _ = try serverController.prepareEnvironment()
        guard let projectDirectory = serverController.projectDirectory else {
            throw LocalServerError.projectMissing
        }
        let inputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qieman-import-\(UUID().uuidString).txt")
        try text.write(to: inputURL, atomically: true, encoding: .utf8)
        _ = try runPythonScript(
            projectDirectory: projectDirectory,
            scriptRelativePath: scriptRelativePath,
            arguments: ["--input", inputURL.path]
        )
    }

    private func runPrepareImportScript(
        projectDirectory: URL,
        target: PersonalDataImportTarget,
        source: PersonalDataImportSource,
        inputURL: URL
    ) throws -> String {
        try runPythonScript(
            projectDirectory: projectDirectory,
            scriptRelativePath: "scripts/prepare_personal_import.py",
            arguments: [
                "--target", target.prepareTargetValue,
                "--source", source.prepareSourceValue,
                "--input", inputURL.path,
            ]
        )
    }

    private func runPythonScript(projectDirectory: URL, scriptRelativePath: String, arguments: [String]) throws -> String {
        let env = ProcessInfo.processInfo.environment
        let pythonPath = env["QIEMAN_PYTHON"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin/python3"
        let scriptURL = projectDirectory.appendingPathComponent(scriptRelativePath)

        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw LocalServerError.pythonMissing(pythonPath)
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw LocalServerError.startupFailed("缺少导入脚本：\(scriptURL.lastPathComponent)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptURL.path] + arguments
        process.currentDirectoryURL = projectDirectory
        process.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw LocalServerError.startupFailed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchPlatformIfPossible() async throws -> PlatformPayload? {
        let prodCode = form.prodCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prodCode.isEmpty else {
            return nil
        }
        return try await platformClient.fetchPlatformPayload(prodCode: prodCode)
    }

    func refreshDataForSectionIfNeeded(_ section: AppSection) {
        guard !isRefreshing else { return }

        switch section {
        case .overview:
            guard !hasForumPosts || !hasPlatformActions else { return }
        case .platform:
            guard !hasPlatformActions else { return }
        case .forum:
            guard !hasForumPosts else { return }
        default:
            return
        }

        if (section == .overview || section == .forum), !form.mode.producesPostRecords {
            form.mode = cookieAvailable ? .followingPosts : .groupManager
        }

        Task { try? await refreshLatest(persist: false, updateNotice: false) }
    }

    private func ensureSelectedPlatformAction(preferredID: String? = nil) {
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

    private func refreshLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLoginEnabled = false
        }
    }

    private func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
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

    private func scheduleAutomaticUpdateCheckIfNeeded() {
        let lastCheckDate = UserDefaults.standard.object(forKey: updateAutoCheckDefaultsKey) as? Date
        if let lastCheckDate, Date().timeIntervalSince(lastCheckDate) < updateAutoCheckInterval {
            return
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.checkForUpdates(userInitiated: false)
        }
    }

    private func persistManagerWatchSettings(restartLoop: Bool = true) {
        guard let managerWatchFileURL else { return }
        do {
            try managerWatchStore.save(managerWatchSettings, to: managerWatchFileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        if restartLoop {
            restartManagerWatchLoop(immediate: false)
        }
    }

    private func setManagerWatchEnabled(_ isEnabled: Bool) async {
        if isEnabled {
            let granted = await notificationManager.requestAuthorizationIfNeeded()
            guard granted else {
                managerWatchSettings.isEnabled = false
                managerWatchSettings.lastErrorMessage = "系统通知权限未开启"
                persistManagerWatchSettings(restartLoop: false)
                errorMessage = "系统通知权限未开启。请在系统设置里允许“且慢主理人”的通知后再开启巡检。"
                return
            }
            if managerWatchSettings.prodCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                managerWatchSettings.prodCode = form.prodCode.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if managerWatchSettings.managerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                managerWatchSettings.managerName = preferredManagerWatchName
            }
        }

        managerWatchSettings.isEnabled = isEnabled
        managerWatchSettings.lastErrorMessage = nil
        persistManagerWatchSettings(restartLoop: false)
        restartManagerWatchLoop(immediate: isEnabled)
        noticeMessage = isEnabled
            ? "已开启主理人通知巡检，首次会先静默建立基线。"
            : "已关闭主理人通知巡检。"
    }

    private func restartManagerWatchLoop(immediate: Bool) {
        managerWatchTask?.cancel()
        managerWatchTask = nil

        guard managerWatchSettings.isEnabled else { return }

        managerWatchTask = Task { [weak self] in
            guard let self else { return }
            if immediate {
                await self.performManagerWatchPoll(sendNotifications: true, manual: false)
            }
            while !Task.isCancelled {
                let interval = UInt64(max(5, self.managerWatchSettings.intervalMinutes) * 60) * 1_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                await self.performManagerWatchPoll(sendNotifications: true, manual: false)
            }
        }
    }

    private func performManagerWatchPoll(sendNotifications: Bool, manual: Bool) async {
        let prodCode = managerWatchSettings.prodCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let managerName = managerWatchSettings.managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prodCode.isEmpty, !managerName.isEmpty else {
            if manual {
                errorMessage = "通知巡检需要产品代码和主理人名称。"
            }
            return
        }
        guard managerWatchSettings.watchForum || managerWatchSettings.watchPlatform else {
            if manual {
                errorMessage = "通知巡检至少要开启“调仓”或“发言”其中一项。"
            }
            return
        }

        managerWatchSettings.lastCheckedAt = Self.timestampString()

        var updateTitles: [String] = []
        var pendingNotifications: [(title: String, subtitle: String, body: String, deepLink: NotificationDeepLinkPayload?)] = []
        var encounteredErrors: [String] = []

        if managerWatchSettings.watchForum {
            do {
                let snapshot = try await fetchForumWatchSnapshot(prodCode: prodCode, managerName: managerName)
                let previousID = managerWatchSettings.latestSeenForumRecordID
                let newRecords = unseenItems(snapshot.records, previousID: previousID)
                if previousID != nil, !newRecords.isEmpty, sendNotifications {
                    if let latest = newRecords.first {
                        pendingNotifications.append((
                            title: "\(managerName) 有 \(newRecords.count) 条新发言",
                            subtitle: prodCode,
                            body: "\(latest.createdAt ?? "刚刚") · \(latest.titleText)",
                            deepLink: NotificationDeepLinkPayload(
                                type: .forumRecord,
                                targetID: latest.id,
                                prodCode: prodCode,
                                managerName: managerName
                            )
                        ))
                    }
                    updateTitles.append("新发言 \(newRecords.count) 条")
                }
                managerWatchSettings.latestSeenForumRecordID = snapshot.records.first?.id
            } catch {
                encounteredErrors.append("发言巡检失败：\(error.localizedDescription)")
            }
        }

        if managerWatchSettings.watchPlatform {
            do {
                let platform = try await platformClient.fetchPlatformPayload(prodCode: prodCode)
                let actions = platform.actions ?? []
                let previousID = managerWatchSettings.latestSeenPlatformActionID
                let newActions = unseenItems(actions, previousID: previousID)
                if previousID != nil, !newActions.isEmpty, sendNotifications {
                    if let latest = newActions.first {
                        pendingNotifications.append((
                            title: "\(managerName) 有 \(newActions.count) 条新调仓",
                            subtitle: prodCode,
                            body: platformNotificationBody(for: latest),
                            deepLink: NotificationDeepLinkPayload(
                                type: .platformAction,
                                targetID: latest.id,
                                prodCode: prodCode,
                                managerName: managerName
                            )
                        ))
                    }
                    updateTitles.append("新调仓 \(newActions.count) 条")
                }
                managerWatchSettings.latestSeenPlatformActionID = actions.first?.id
            } catch {
                encounteredErrors.append("调仓巡检失败：\(error.localizedDescription)")
            }
        }

        if encounteredErrors.isEmpty {
            managerWatchSettings.lastSuccessAt = managerWatchSettings.lastCheckedAt
            managerWatchSettings.lastErrorMessage = nil
        } else {
            managerWatchSettings.lastErrorMessage = encounteredErrors.joined(separator: "；")
            if manual {
                errorMessage = managerWatchSettings.lastErrorMessage ?? ""
            }
        }

        persistManagerWatchSettings(restartLoop: false)

        for item in pendingNotifications {
            await notificationManager.send(
                title: item.title,
                subtitle: item.subtitle,
                body: item.body,
                deepLink: item.deepLink
            )
        }

        if manual {
            if !pendingNotifications.isEmpty {
                noticeMessage = "巡检完成，已推送 \(updateTitles.joined(separator: "，"))。"
            } else if encounteredErrors.isEmpty {
                noticeMessage = "巡检完成，目前没有新的主理人调仓或发言。"
            }
        }
    }

    private func fetchForumWatchSnapshot(prodCode: String, managerName: String) async throws -> SnapshotPayload {
        var watchForm = QueryFormState()
        watchForm.mode = .groupManager
        watchForm.prodCode = prodCode
        watchForm.managerName = managerName
        watchForm.userName = managerName
        watchForm.pages = "1"
        watchForm.pageSize = "10"
        return try await nativeClient.fetchSnapshot(form: watchForm, persist: false, outputDirectory: nil)
    }

    private func unseenItems<T: Identifiable>(_ items: [T], previousID: T.ID?) -> [T] where T.ID: Equatable {
        guard let previousID else { return [] }
        if let index = items.firstIndex(where: { $0.id == previousID }) {
            guard index > 0 else { return [] }
            return Array(items.prefix(index))
        }
        return Array(items.prefix(min(items.count, 3)))
    }

    private func platformNotificationBody(for action: PlatformActionPayload) -> String {
        let time = action.txnDate ?? action.createdAt ?? "刚刚"
        let target = action.fundName ?? action.fundCode ?? "未知标的"
        let change = action.valuationChangePct.map { String(format: "%+.2f%%", $0) } ?? "—"
        return "\(time) · \(action.displayTitle) · \(target) · 估值变化 \(change)"
    }

    private func handleNotificationDeepLink(_ payload: NotificationDeepLinkPayload) {
        revealMainWindowIfNeeded()
        switch payload.type {
        case .platformAction:
            openPlatformAction(payload)
        case .forumRecord:
            openForumRecord(payload)
        }
    }

    private func revealMainWindowIfNeeded() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if NSApplication.shared.windows.isEmpty {
            _ = NSApplication.shared.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
        } else {
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private func openPlatformAction(_ payload: NotificationDeepLinkPayload) {
        selectedSection = .platform
        selectedPlatformActionID = payload.targetID

        let existingActions = platformPayload?.actions ?? []
        if existingActions.contains(where: { $0.id == payload.targetID }) {
            return
        }

        let prodCode = (payload.prodCode ?? managerWatchSettings.prodCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prodCode.isEmpty else {
            return
        }

        Task {
            do {
                let platform = try await platformClient.fetchPlatformPayload(prodCode: prodCode)
                platformPayload = platform
                ensureSelectedPlatformAction(preferredID: payload.targetID)
                if selectedPlatformActionID == payload.targetID {
                    noticeMessage = "已定位到通知对应的调仓详情。"
                } else {
                    noticeMessage = "已刷新调仓列表，原通知对应动作可能已归档。"
                }
            } catch {
                errorMessage = "定位通知调仓失败：\(error.localizedDescription)"
            }
        }
    }

    private func openForumRecord(_ payload: NotificationDeepLinkPayload) {
        selectedSection = .forum
        selectedPostID = payload.targetID

        if forumRecords.contains(where: { $0.id == payload.targetID }) {
            return
        }

        let prodCode = (payload.prodCode ?? managerWatchSettings.prodCode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let managerName = (payload.managerName ?? managerWatchSettings.managerName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prodCode.isEmpty, !managerName.isEmpty else {
            return
        }

        Task {
            do {
                let snapshot = try await fetchForumWatchSnapshot(prodCode: prodCode, managerName: managerName)
                currentSnapshot = snapshot
                commentsPayload = nil
                selectedPostID = snapshot.records.first(where: { $0.id == payload.targetID })?.id ?? snapshot.records.first?.id
                if selectedPostID == payload.targetID {
                    noticeMessage = "已定位到通知对应的发言详情。"
                } else {
                    noticeMessage = "已刷新发言列表，原通知对应发言可能已归档。"
                }
            } catch {
                errorMessage = "定位通知发言失败：\(error.localizedDescription)"
            }
        }
    }

    private func rebuildNativeStatus() {
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
            snapshotCount: history.count,
            latestSnapshot: history.first,
            preferredSnapshotName: snapshotStore.preferredSnapshot(from: history, preferPosts: true)?.fileName,
            defaultForm: defaultForm
        )
    }

    private var nativeCookieExists: Bool {
        guard let cookieURL = serverController.cookieFileURL else { return false }
        return FileManager.default.fileExists(atPath: cookieURL.path)
    }

    private var managerWatchFileURL: URL? {
        dataDirectoryURL?.appendingPathComponent("manager-watch-settings.json", isDirectory: false)
    }

    private var preferredManagerWatchName: String {
        let primary = form.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty {
            return primary
        }
        let secondary = form.managerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return secondary.isEmpty ? "ETF拯救世界" : secondary
    }

    private func sortInvestmentPlans(_ lhs: PersonalInvestmentPlan, _ rhs: PersonalInvestmentPlan) -> Bool {
        let lhsRank = investmentPlanStatusRank(lhs)
        let rhsRank = investmentPlanStatusRank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        let lhsDate = lhs.nextExecutionDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsDate = rhs.nextExecutionDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if lhsDate != rhsDate {
            if lhsDate.isEmpty { return false }
            if rhsDate.isEmpty { return true }
            return lhsDate < rhsDate
        }
        return lhs.fundName.localizedStandardCompare(rhs.fundName) == .orderedAscending
    }

    private func investmentPlanStatusRank(_ plan: PersonalInvestmentPlan) -> Int {
        if plan.isActivePlan { return 0 }
        if plan.isPausedPlan { return 1 }
        return 2
    }

    private func personalFundKey(code: String?, name: String?) -> String {
        personalAssetKey(assetType: .fund, code: code, name: name)
    }

    private func personalAssetKey(assetType: PersonalAssetType, code: String?, name: String?) -> String {
        if let code = normalizedCode(code) {
            return "\(assetType.rawValue):code:\(code)"
        }
        let normalizedName = (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
        return "\(assetType.rawValue):name:\(normalizedName)"
    }

    private func normalizedCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
