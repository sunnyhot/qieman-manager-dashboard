import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let qiemanNotificationDeepLink = Notification.Name("qieman.notificationDeepLink")
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private static let storageKey = "qieman.dashboard.appearance"

    static func load() -> AppAppearance {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AppAppearance(rawValue: raw) else { return .system }
        return value
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
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
    @Published var marketIndexQuotes: [MarketIndexKind: MarketIndexQuote] = [:]
    @Published var managerWatchSettings = ManagerWatchSettings.default
    @Published var menuBarTickerSettings = MenuBarTickerSettings.load()

    @Published var selectedPostID: String?
    @Published var selectedPlatformActionID: String?
    @Published var commentSortType = "hot"
    @Published var onlyManagerReplies = false
    @Published var launchAtLoginEnabled = false
    @Published var appearance: AppAppearance = AppAppearance.load() { didSet { appearance.save() } }

    @Published var isBootstrapping = false
    @Published var isRefreshing = false
    @Published var isCheckingAuth = false
    @Published var isLoadingComments = false
    @Published var isPresentingLoginSheet = false
    @Published var showAdvancedParams = false
    @Published var isRefreshingPortfolio = false
    @Published var isRefreshingMarketIndices = false
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
    private let portfolioAutoRefreshIntervalSeconds: UInt64 = 60

    private var didApplyDefaultForm = false
    private var didStart = false
    private var managerWatchTask: Task<Void, Never>?
    private var personalAssetAutomationTask: Task<Void, Never>?
    private var portfolioAutoRefreshTask: Task<Void, Never>?
    private var activeCommentsRequestKey = ""
    private var isApplyingPersonalAssetAutomation = false
    private var cancellables = Set<AnyCancellable>()

    private var _cachedAssetRows: [PersonalAssetAggregateRow]?
    private var _cachedAssetSummary: PersonalAssetAggregateSummary?
    private var _cachedMonthlyPlatformSummary: [PlatformMonthSummary]?
    private var _cachedActiveInvestmentPlans: [PersonalInvestmentPlan]?
    private var _cachedPausedInvestmentPlans: [PersonalInvestmentPlan]?
    private var _cachedEndedInvestmentPlans: [PersonalInvestmentPlan]?
    private var _cachedInvestmentPlanSummary: PersonalInvestmentPlanSummary?
    private var _cachedPendingTradeSummary: PersonalPendingTradeSummary?

    private func clearCachedComputedProperties() {
        _cachedAssetRows = nil
        _cachedAssetSummary = nil
        _cachedMonthlyPlatformSummary = nil
        _cachedActiveInvestmentPlans = nil
        _cachedPausedInvestmentPlans = nil
        _cachedEndedInvestmentPlans = nil
        _cachedInvestmentPlanSummary = nil
        _cachedPendingTradeSummary = nil
    }

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
        portfolioAutoRefreshTask?.cancel()
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
                noticeMessage = "原生直连暂时不可用，已保留当前界面数据。"
            }
        }

        if !activeUserPortfolioHoldings.isEmpty {
            try? await refreshUserPortfolio(updateNotice: false)
        }
        await refreshMarketIndicesIfNeeded()

        await applyPersonalAssetAutomation(updateNotice: false)
        restartManagerWatchLoop(immediate: false)
        restartPersonalAssetAutomationLoop()
        restartPortfolioAutoRefreshLoop()
        scheduleAutomaticUpdateCheckIfNeeded()
    }

    func refreshLatest(persist: Bool, updateNotice: Bool = true) async throws {
        isRefreshing = true
        errorMessage = ""
        defer { isRefreshing = false }

        let currentForm = form
        async let snapshotTask = nativeClient.fetchSnapshot(form: currentForm, persist: false, outputDirectory: nil)
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
            ensureSelectedForumPost()
        }

        if let platform = refreshedPlatform {
            platformPayload = platform
            _cachedMonthlyPlatformSummary = nil
            ensureSelectedPlatformAction()
        }

        rebuildNativeStatus()

        guard refreshedSnapshot != nil || refreshedPlatform != nil else {
            let message = failures.isEmpty ? "原生刷新失败，论坛和平台数据都没有拉到。" : failures.joined(separator: "；")
            errorMessage = message
            throw LiveRefreshError(message: message)
        }

        if failures.isEmpty {
            if updateNotice {
                noticeMessage = "已通过原生抓取刷新到最新结果。"
            }
        } else {
            errorMessage = failures.joined(separator: "；")
            if updateNotice {
                noticeMessage = "已刷新可用数据，但有部分内容拉取失败。"
            }
        }

        await refreshMarketIndicesIfNeeded()
    }

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

    func savePortfolioFromDraft(mode: PersonalDataSaveMode = .merge) {
        guard let portfolioFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存持仓。"
            return
        }
        do {
            let importedHoldings = try importedPortfolioHoldings(from: portfolioDraft)
            let nextHoldings: [UserPortfolioHolding]
            switch mode {
            case .merge:
                nextHoldings = portfolioStore.merging(importedHoldings, into: userPortfolioHoldings)
            case .replace:
                nextHoldings = importedHoldings
            }

            userPortfolioHoldings = nextHoldings
            userPortfolioSnapshot = nil
            clearCachedComputedProperties()
            try portfolioStore.save(nextHoldings, to: portfolioFileURL)
            portfolioDraft = ""

            let savedCount = importedHoldings.count
            let modeText = mode.actionText
            noticeMessage = "已\(modeText)保存 \(savedCount) 条个人持仓，正在按代码补全名称。"
            Task {
                let resolvedCount = await resolveAndPersistPortfolioNames()
                try? await refreshUserPortfolio(updateNotice: false)
                if resolvedCount > 0 {
                    noticeMessage = "已\(modeText)保存 \(savedCount) 条个人持仓，并通过代码补全 \(resolvedCount) 个名称。"
                } else {
                    noticeMessage = "已\(modeText)保存 \(savedCount) 条个人持仓。"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePendingTradesFromDraft(mode: PersonalDataSaveMode = .merge) {
        guard let pendingTradeFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存买入中记录。"
            return
        }
        do {
            let importedTrades = try importedPendingTrades(from: pendingTradesDraft)
            let nextTrades: [PersonalPendingTrade]
            switch mode {
            case .merge:
                nextTrades = pendingTradesStore.merging(importedTrades, into: pendingTrades)
            case .replace:
                nextTrades = importedTrades.sorted { $0.occurredAt > $1.occurredAt }
            }

            pendingTrades = nextTrades
            pendingTradesDraft = ""
            clearCachedComputedProperties()
            try pendingTradesStore.save(nextTrades, to: pendingTradeFileURL)
            noticeMessage = "已\(mode.actionText)保存 \(importedTrades.count) 条买入中记录。"
            Task { await applyPersonalAssetAutomation() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveInvestmentPlansFromDraft(mode: PersonalDataSaveMode = .merge) {
        guard let investmentPlanFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存定投计划。"
            return
        }
        do {
            let importedPlans = try importedInvestmentPlans(from: investmentPlansDraft)
            let nextPlans: [PersonalInvestmentPlan]
            switch mode {
            case .merge:
                nextPlans = investmentPlansStore.merging(importedPlans, into: investmentPlans).sorted(by: sortInvestmentPlans)
            case .replace:
                nextPlans = importedPlans.sorted(by: sortInvestmentPlans)
            }

            investmentPlans = nextPlans
            investmentPlansDraft = ""
            clearCachedComputedProperties()
            try investmentPlansStore.save(nextPlans, to: investmentPlanFileURL)
            noticeMessage = "已\(mode.actionText)保存 \(importedPlans.count) 条定投计划。"
            Task { await applyPersonalAssetAutomation() }
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
            clearCachedComputedProperties()
            portfolioDraft = ""
            noticeMessage = "已清空个人持仓。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePersonalAssetEntry(_ row: PersonalAssetAggregateRow, scope: PersonalAssetDeleteScope) {
        let holdingIDs = Set(scope.includesHolding ? [
            row.rawHolding?.id,
            row.holdingRow?.holding.id,
            row.archivedHolding?.id,
        ].compactMap { $0 } : [])
        let pendingTradeIDs = Set(scope.includesPendingTrades ? row.pendingTrades.map(\.id) : [])
        let investmentPlanIDs = Set(scope.includesInvestmentPlans ? row.plans.map(\.id) : [])

        do {
            var deletedParts: [String] = []
            var shouldRefreshPortfolio = false

            if !holdingIDs.isEmpty {
                guard let portfolioFileURL else {
                    throw LiveRefreshError(message: "应用数据目录还没准备好，暂时无法删除持仓。")
                }

                let nextHoldings = userPortfolioHoldings.filter { !holdingIDs.contains($0.id) }
                if nextHoldings.count != userPortfolioHoldings.count {
                    userPortfolioHoldings = nextHoldings
                    userPortfolioSnapshot = nil
                    if nextHoldings.isEmpty {
                        try portfolioStore.delete(at: portfolioFileURL)
                    } else {
                        try portfolioStore.save(nextHoldings, to: portfolioFileURL)
                        shouldRefreshPortfolio = !activeUserPortfolioHoldings.isEmpty
                    }
                    deletedParts.append(row.hasArchivedHolding && !row.hasHolding ? "归档持仓" : "已持有")
                }
            }

            if !pendingTradeIDs.isEmpty {
                guard let pendingTradeFileURL else {
                    throw LiveRefreshError(message: "应用数据目录还没准备好，暂时无法删除买入中记录。")
                }

                let nextTrades = pendingTrades.filter { !pendingTradeIDs.contains($0.id) }
                let deletedCount = pendingTrades.count - nextTrades.count
                if deletedCount > 0 {
                    pendingTrades = nextTrades.sorted { $0.occurredAt > $1.occurredAt }
                    if pendingTrades.isEmpty {
                        try pendingTradesStore.delete(at: pendingTradeFileURL)
                    } else {
                        try pendingTradesStore.save(pendingTrades, to: pendingTradeFileURL)
                    }
                    deletedParts.append("买入中 \(deletedCount) 条")
                }
            }

            if !investmentPlanIDs.isEmpty {
                guard let investmentPlanFileURL else {
                    throw LiveRefreshError(message: "应用数据目录还没准备好，暂时无法删除定投计划。")
                }

                let nextPlans = investmentPlans.filter { !investmentPlanIDs.contains($0.id) }
                let deletedCount = investmentPlans.count - nextPlans.count
                if deletedCount > 0 {
                    investmentPlans = nextPlans.sorted(by: sortInvestmentPlans)
                    if investmentPlans.isEmpty {
                        try investmentPlansStore.delete(at: investmentPlanFileURL)
                    } else {
                        try investmentPlansStore.save(investmentPlans, to: investmentPlanFileURL)
                    }
                    deletedParts.append("计划档案 \(deletedCount) 条")
                }
            }

            guard !deletedParts.isEmpty else {
                noticeMessage = "没有找到可删除的本地记录。"
                return
            }

            clearCachedComputedProperties()
            let itemText = row.fundCode.map { "\(row.fundName)（\($0)）" } ?? row.fundName
            noticeMessage = "已删除 \(itemText) 的\(deletedParts.joined(separator: "、"))记录。"

            if shouldRefreshPortfolio {
                Task { try? await refreshUserPortfolio(updateNotice: false) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func archivePersonalAssetHolding(_ row: PersonalAssetAggregateRow) {
        setPersonalAssetHoldingArchived(row, isArchived: true)
    }

    func restorePersonalAssetHolding(_ row: PersonalAssetAggregateRow) {
        setPersonalAssetHoldingArchived(row, isArchived: false)
    }

    private func setPersonalAssetHoldingArchived(_ row: PersonalAssetAggregateRow, isArchived: Bool) {
        let targetHolding = isArchived
            ? (row.rawHolding ?? row.holdingRow?.holding)
            : row.archivedHolding
        guard let targetHolding else {
            errorMessage = isArchived ? "这条资产没有可归档的已持有记录。" : "这条资产没有可恢复的归档记录。"
            return
        }
        guard let existingIndex = userPortfolioHoldings.firstIndex(where: { $0.id == targetHolding.id }) else {
            errorMessage = "没有找到这条持仓的本地保存记录。"
            return
        }
        guard let portfolioFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法调整持仓归档。"
            return
        }

        if !isArchived {
            let duplicateActiveHolding = userPortfolioHoldings.contains { holding in
                guard holding.id != targetHolding.id, !holding.isArchived else { return false }
                guard holding.assetType == targetHolding.assetType else { return false }
                if targetHolding.assetType == .stock {
                    guard holding.detectedMarket == targetHolding.detectedMarket else { return false }
                } else {
                    guard holding.detectedFundMarket == targetHolding.detectedFundMarket else { return false }
                }
                return holding.normalizedFundCode.caseInsensitiveCompare(targetHolding.normalizedFundCode) == .orderedSame
            }
            guard !duplicateActiveHolding else {
                errorMessage = "本地已经有同代码的活跃持仓，请先合并或删除重复项。"
                return
            }
        }

        do {
            var nextHoldings = userPortfolioHoldings
            nextHoldings[existingIndex] = UserPortfolioHolding(
                id: targetHolding.id,
                fundCode: targetHolding.fundCode,
                assetType: targetHolding.assetType,
                units: targetHolding.units,
                costPrice: targetHolding.costPrice,
                displayName: targetHolding.displayName,
                stockMarket: targetHolding.stockMarket,
                fundMarket: targetHolding.fundMarket,
                isArchived: isArchived,
                archivedAt: isArchived ? timestampNow() : nil
            )
            userPortfolioHoldings = nextHoldings
            userPortfolioSnapshot = nil
            clearCachedComputedProperties()
            try portfolioStore.save(nextHoldings, to: portfolioFileURL)

            let itemText = row.fundCode.map { "\(row.fundName)（\($0)）" } ?? row.fundName
            noticeMessage = isArchived ? "已归档 \(itemText) 的持仓记录。" : "已恢复 \(itemText) 的持仓记录。"
            if !activeUserPortfolioHoldings.isEmpty {
                Task { try? await refreshUserPortfolio(updateNotice: false) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func updatePersonalAssetHolding(
        _ row: PersonalAssetAggregateRow,
        codeText: String,
        unitsText: String,
        costPriceText: String,
        displayNameText: String
    ) -> Bool {
        guard let existingHolding = row.rawHolding ?? row.holdingRow?.holding else {
            errorMessage = "这条资产还没有已持有记录，暂时无法编辑持仓。"
            return false
        }
        guard let existingIndex = userPortfolioHoldings.firstIndex(where: { $0.id == existingHolding.id }) else {
            errorMessage = "没有找到这条持仓的本地保存记录。"
            return false
        }

        let fundCode = normalizedManualAssetCode(assetType: existingHolding.assetType, codeText: codeText)
        guard !fundCode.isEmpty else {
            errorMessage = "请输入\(existingHolding.assetType.displayName)代码。"
            return false
        }
        guard let units = decimalInputValue(unitsText), units > 0 else {
            errorMessage = "请输入大于 0 的份额。"
            return false
        }

        let trimmedCost = costPriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let costPrice: Double?
        if trimmedCost.isEmpty {
            costPrice = nil
        } else {
            guard let parsedCost = decimalInputValue(trimmedCost), parsedCost > 0 else {
                errorMessage = "成本价为空或大于 0。"
                return false
            }
            costPrice = parsedCost
        }

        guard let portfolioFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存持仓。"
            return false
        }

        let market = manualStockMarket(assetType: existingHolding.assetType, codeText: codeText)
            ?? existingHolding.stockMarket
            ?? existingHolding.detectedMarket
        let fundMarket = manualFundMarket(assetType: existingHolding.assetType, codeText: codeText)
            ?? existingHolding.fundMarket
            ?? existingHolding.detectedFundMarket
        let hasDuplicate = userPortfolioHoldings.contains { holding in
            guard holding.id != existingHolding.id else { return false }
            guard !holding.isArchived else { return false }
            guard holding.assetType == existingHolding.assetType else { return false }
            if existingHolding.assetType == .stock {
                guard holding.detectedMarket == market else { return false }
            } else {
                guard holding.detectedFundMarket == fundMarket else { return false }
            }
            return holding.normalizedFundCode.caseInsensitiveCompare(fundCode) == .orderedSame
        }
        guard !hasDuplicate else {
            errorMessage = "本地已经有同代码的\(existingHolding.assetType.displayName)持仓，请先合并或删除重复项。"
            return false
        }

        do {
            var nextHoldings = userPortfolioHoldings
            nextHoldings[existingIndex] = UserPortfolioHolding(
                id: existingHolding.id,
                fundCode: fundCode,
                assetType: existingHolding.assetType,
                units: units,
                costPrice: costPrice.map(normalizedCostPrice),
                displayName: normalizedOptionalName(displayNameText),
                stockMarket: market,
                fundMarket: fundMarket,
                isArchived: existingHolding.isArchived,
                archivedAt: existingHolding.archivedAt
            )
            userPortfolioHoldings = nextHoldings
            userPortfolioSnapshot = nil
            clearCachedComputedProperties()
            try portfolioStore.save(nextHoldings, to: portfolioFileURL)

            let itemText = normalizedOptionalName(displayNameText) ?? row.fundName
            noticeMessage = "已更新 \(itemText)（\(fundCode)）的持仓明细。"
            Task { try? await refreshUserPortfolio(updateNotice: false) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateInvestmentPlansStatus(_ row: PersonalAssetAggregateRow, status: String, activeOnly: Bool = false, archivedOnly: Bool = false) {
        let targetIDs = Set(row.plans.filter { plan in
            if activeOnly {
                return plan.isActivePlan
            }
            if archivedOnly {
                return plan.isPausedPlan || plan.isEndedPlan
            }
            return true
        }.map(\.id))
        guard !targetIDs.isEmpty else {
            noticeMessage = "没有找到需要调整状态的计划。"
            return
        }
        guard let investmentPlanFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法调整计划状态。"
            return
        }

        do {
            let nextPlans = investmentPlans.map { plan -> PersonalInvestmentPlan in
                guard targetIDs.contains(plan.id) else { return plan }
                return PersonalInvestmentPlan(
                    id: plan.id,
                    planTypeLabel: plan.planTypeLabel,
                    fundName: plan.fundName,
                    fundCode: plan.fundCode,
                    scheduleText: plan.scheduleText,
                    amountText: plan.amountText,
                    minAmount: plan.minAmount,
                    maxAmount: plan.maxAmount,
                    investedPeriods: plan.investedPeriods,
                    cumulativeInvestedAmount: plan.cumulativeInvestedAmount,
                    paymentMethod: plan.paymentMethod,
                    nextExecutionDate: plan.nextExecutionDate,
                    status: status,
                    note: plan.note
                )
            }
            investmentPlans = nextPlans.sorted(by: sortInvestmentPlans)
            clearCachedComputedProperties()
            try investmentPlansStore.save(investmentPlans, to: investmentPlanFileURL)
            let itemText = row.fundCode.map { "\(row.fundName)（\($0)）" } ?? row.fundName
            noticeMessage = "已将 \(itemText) 的 \(targetIDs.count) 条计划调整为\(status)。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateInvestmentPlanStatus(_ planID: UUID, status: String) {
        guard let investmentPlanFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法调整计划状态。"
            return
        }
        guard let existingPlan = investmentPlans.first(where: { $0.id == planID }) else {
            errorMessage = "没有找到这条定投计划。"
            return
        }

        do {
            let normalizedStatus = normalizedInvestmentPlanStatus(status)
            let nextPlans = investmentPlans.map { plan -> PersonalInvestmentPlan in
                guard plan.id == planID else { return plan }
                return replacingInvestmentPlan(plan, status: normalizedStatus)
            }
            investmentPlans = nextPlans.sorted(by: sortInvestmentPlans)
            clearCachedComputedProperties()
            try investmentPlansStore.save(investmentPlans, to: investmentPlanFileURL)
            let itemText = existingPlan.fundCode.map { "\(existingPlan.fundName)（\($0)）" } ?? existingPlan.fundName
            noticeMessage = "已将 \(itemText) 的计划调整为\(normalizedStatus)。"
            Task { await applyPersonalAssetAutomation() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addPendingTrade(
        occurredAt: String,
        actionLabel: String,
        fundName: String,
        fundCode: String,
        targetFundName: String,
        targetFundCode: String,
        amountText: String,
        status: String,
        note: String
    ) -> Bool {
        guard let pendingTradeFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法添加买入中记录。"
            return false
        }
        guard let trade = validatedPendingTrade(
            id: UUID(),
            occurredAt: occurredAt,
            actionLabel: actionLabel,
            fundName: fundName,
            fundCode: fundCode,
            targetFundName: targetFundName,
            targetFundCode: targetFundCode,
            amountText: amountText,
            status: status,
            note: note
        ) else {
            return false
        }

        do {
            pendingTrades.append(trade)
            pendingTrades.sort { $0.occurredAt > $1.occurredAt }
            clearCachedComputedProperties()
            try pendingTradesStore.save(pendingTrades, to: pendingTradeFileURL)
            noticeMessage = "已添加 \(trade.displayTitle) 的买入中记录。"
            Task { await applyPersonalAssetAutomation() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updatePendingTrade(
        _ tradeID: UUID,
        occurredAt: String,
        actionLabel: String,
        fundName: String,
        fundCode: String,
        targetFundName: String,
        targetFundCode: String,
        amountText: String,
        status: String,
        note: String
    ) -> Bool {
        guard let existingIndex = pendingTrades.firstIndex(where: { $0.id == tradeID }) else {
            errorMessage = "没有找到这条买入中记录。"
            return false
        }
        guard let pendingTradeFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存买入中记录。"
            return false
        }
        guard let trade = validatedPendingTrade(
            id: tradeID,
            occurredAt: occurredAt,
            actionLabel: actionLabel,
            fundName: fundName,
            fundCode: fundCode,
            targetFundName: targetFundName,
            targetFundCode: targetFundCode,
            amountText: amountText,
            status: status,
            note: note
        ) else {
            return false
        }

        do {
            pendingTrades[existingIndex] = trade
            pendingTrades.sort { $0.occurredAt > $1.occurredAt }
            clearCachedComputedProperties()
            try pendingTradesStore.save(pendingTrades, to: pendingTradeFileURL)
            noticeMessage = "已更新 \(trade.displayTitle) 的买入中记录。"
            Task { await applyPersonalAssetAutomation() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePendingTrade(_ tradeID: UUID) {
        guard let pendingTradeFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法删除买入中记录。"
            return
        }
        guard let existingTrade = pendingTrades.first(where: { $0.id == tradeID }) else {
            errorMessage = "没有找到这条买入中记录。"
            return
        }

        do {
            pendingTrades = pendingTrades.filter { $0.id != tradeID }
            clearCachedComputedProperties()
            if pendingTrades.isEmpty {
                try pendingTradesStore.delete(at: pendingTradeFileURL)
            } else {
                try pendingTradesStore.save(pendingTrades, to: pendingTradeFileURL)
            }
            noticeMessage = "已删除 \(existingTrade.displayTitle) 的买入中记录。"
            Task { await applyPersonalAssetAutomation() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addInvestmentPlan(
        planTypeLabel: String,
        fundName: String,
        fundCode: String,
        scheduleText: String,
        amountText: String,
        investedPeriodsText: String,
        cumulativeInvestedAmountText: String,
        paymentMethod: String,
        nextExecutionDate: String,
        status: String,
        note: String
    ) -> Bool {
        guard let investmentPlanFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法添加定投计划。"
            return false
        }
        guard let plan = validatedInvestmentPlan(
            id: UUID(),
            planTypeLabel: planTypeLabel,
            fundName: fundName,
            fundCode: fundCode,
            scheduleText: scheduleText,
            amountText: amountText,
            investedPeriodsText: investedPeriodsText,
            cumulativeInvestedAmountText: cumulativeInvestedAmountText,
            paymentMethod: paymentMethod,
            nextExecutionDate: nextExecutionDate,
            status: status,
            note: note
        ) else {
            return false
        }

        do {
            investmentPlans.append(plan)
            investmentPlans.sort(by: sortInvestmentPlans)
            clearCachedComputedProperties()
            try investmentPlansStore.save(investmentPlans, to: investmentPlanFileURL)
            let itemText = plan.fundCode.map { "\(plan.fundName)（\($0)）" } ?? plan.fundName
            noticeMessage = "已添加 \(itemText) 的定投计划。"
            Task { await applyPersonalAssetAutomation() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateInvestmentPlan(
        _ planID: UUID,
        planTypeLabel: String,
        fundName: String,
        fundCode: String,
        scheduleText: String,
        amountText: String,
        investedPeriodsText: String,
        cumulativeInvestedAmountText: String,
        paymentMethod: String,
        nextExecutionDate: String,
        status: String,
        note: String
    ) -> Bool {
        guard let existingIndex = investmentPlans.firstIndex(where: { $0.id == planID }) else {
            errorMessage = "没有找到这条定投计划。"
            return false
        }
        guard let investmentPlanFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法保存定投计划。"
            return false
        }
        guard let plan = validatedInvestmentPlan(
            id: planID,
            planTypeLabel: planTypeLabel,
            fundName: fundName,
            fundCode: fundCode,
            scheduleText: scheduleText,
            amountText: amountText,
            investedPeriodsText: investedPeriodsText,
            cumulativeInvestedAmountText: cumulativeInvestedAmountText,
            paymentMethod: paymentMethod,
            nextExecutionDate: nextExecutionDate,
            status: status,
            note: note
        ) else {
            return false
        }

        do {
            var nextPlans = investmentPlans
            nextPlans[existingIndex] = plan
            investmentPlans = nextPlans.sorted(by: sortInvestmentPlans)
            clearCachedComputedProperties()
            try investmentPlansStore.save(investmentPlans, to: investmentPlanFileURL)

            let itemText = plan.fundCode.map { "\(plan.fundName)（\($0)）" } ?? plan.fundName
            noticeMessage = "已更新 \(itemText) 的定投计划。"
            Task { await applyPersonalAssetAutomation() }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteInvestmentPlan(_ planID: UUID) {
        guard let investmentPlanFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法删除定投计划。"
            return
        }
        guard let existingPlan = investmentPlans.first(where: { $0.id == planID }) else {
            errorMessage = "没有找到这条定投计划。"
            return
        }

        do {
            let nextPlans = investmentPlans.filter { $0.id != planID }
            investmentPlans = nextPlans.sorted(by: sortInvestmentPlans)
            clearCachedComputedProperties()
            if investmentPlans.isEmpty {
                try investmentPlansStore.delete(at: investmentPlanFileURL)
            } else {
                try investmentPlansStore.save(investmentPlans, to: investmentPlanFileURL)
            }
            let itemText = existingPlan.fundCode.map { "\(existingPlan.fundName)（\($0)）" } ?? existingPlan.fundName
            noticeMessage = "已删除 \(itemText) 的定投计划。"
            Task { await applyPersonalAssetAutomation() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addPersonalAssetHolding(
        assetType: PersonalAssetType,
        codeText: String,
        unitsText: String,
        costPriceText: String,
        displayName: String?,
        stockMarket: StockMarket? = nil,
        fundMarket: FundMarket? = nil
    ) -> Bool {
        let fundCode = normalizedManualAssetCode(assetType: assetType, codeText: codeText)
        guard !fundCode.isEmpty else {
            errorMessage = "请输入\(assetType.displayName)代码。"
            return false
        }
        guard let units = decimalInputValue(unitsText), units > 0 else {
            errorMessage = "请输入大于 0 的份额。"
            return false
        }
        guard let costPrice = decimalInputValue(costPriceText), costPrice > 0 else {
            errorMessage = "请输入大于 0 的成本。"
            return false
        }
        guard let portfolioFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法添加持仓。"
            return false
        }

        do {
            let normalizedDisplayName: String? = {
                let value = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? nil : value
            }()
            let market = manualStockMarket(assetType: assetType, codeText: codeText) ?? stockMarket
            let resolvedFundMarket = manualFundMarket(assetType: assetType, codeText: codeText)
                ?? fundMarket
                ?? (assetType == .fund ? UserPortfolioHolding.detectFundMarket(from: fundCode) : nil)
            var nextHoldings = userPortfolioHoldings
            if let existingIndex = nextHoldings.firstIndex(where: {
                guard $0.assetType == assetType else { return false }
                if assetType == .stock, $0.detectedMarket != market { return false }
                if assetType == .fund, $0.detectedFundMarket != resolvedFundMarket { return false }
                return $0.normalizedFundCode.caseInsensitiveCompare(fundCode) == .orderedSame
            }) {
                let existing = nextHoldings[existingIndex]
                let nextUnits = existing.units + units
                let existingCostPrice = existing.costPrice ?? costPrice
                let nextCostPrice = ((existing.units * existingCostPrice) + (units * costPrice)) / nextUnits
                nextHoldings[existingIndex] = UserPortfolioHolding(
                    id: existing.id,
                    fundCode: existing.normalizedFundCode,
                    assetType: existing.assetType,
                    units: nextUnits,
                    costPrice: normalizedCostPrice(nextCostPrice),
                    displayName: normalizedDisplayName ?? existing.normalizedName,
                    stockMarket: existing.stockMarket ?? market,
                    fundMarket: existing.fundMarket ?? resolvedFundMarket,
                    isArchived: false,
                    archivedAt: nil
                )
            } else {
                nextHoldings.append(
                    UserPortfolioHolding(
                        fundCode: fundCode,
                        assetType: assetType,
                        units: units,
                        costPrice: costPrice,
                        displayName: normalizedDisplayName,
                        stockMarket: market,
                        fundMarket: resolvedFundMarket
                    )
                )
            }

            userPortfolioHoldings = nextHoldings
            userPortfolioSnapshot = nil
            clearCachedComputedProperties()
            try portfolioStore.save(nextHoldings, to: portfolioFileURL)

            let nameText = normalizedDisplayName.map { "\($0)（\(fundCode)）" } ?? fundCode
            let typeText = assetType == .stock
                ? (market?.displayName ?? assetType.displayName)
                : (resolvedFundMarket?.displayName ?? assetType.displayName)
            noticeMessage = "已添加\(typeText) \(nameText)，\(personalAssetDecimalText(units)) 份，成本 \(personalAssetDecimalText(costPrice))。"
            Task { try? await refreshUserPortfolio(updateNotice: false) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resolvePersonalAssetCode(_ codeText: String) async -> PersonalAssetCodeResolution? {
        let rawCode = normalizedManualAssetRawCode(codeText)
        guard !rawCode.isEmpty else { return nil }

        let fundCode = normalizedManualAssetCode(assetType: .fund, codeText: rawCode)
        let stockCode = normalizedManualAssetCode(assetType: .stock, codeText: rawCode)
        guard !fundCode.isEmpty || !stockCode.isEmpty else { return nil }
        let detectedFundMarket = UserPortfolioHolding.detectFundMarket(from: fundCode)

        if hasExplicitFundMarket(rawCode) || detectedFundMarket == .onExchange {
            let fundName = fundCode.isEmpty ? nil : await platformClient.resolveAssetName(assetType: .fund, code: fundCode)
            let stockName = detectedFundMarket == .onExchange && !stockCode.isEmpty
                ? await platformClient.resolveAssetName(assetType: .stock, code: stockCode)
                : nil
            return PersonalAssetCodeResolution(
                assetType: .fund,
                code: fundCode,
                displayName: normalizedOptionalName(fundName) ?? normalizedOptionalName(stockName),
                fundMarket: manualFundMarket(assetType: .fund, codeText: rawCode) ?? detectedFundMarket
            )
        }

        if hasExplicitStockMarket(rawCode) {
            let stockName = stockCode.isEmpty ? nil : await platformClient.resolveAssetName(assetType: .stock, code: stockCode)
            return PersonalAssetCodeResolution(
                assetType: .stock,
                code: stockCode,
                displayName: normalizedOptionalName(stockName),
                stockMarket: manualStockMarket(assetType: .stock, codeText: rawCode)
            )
        }

        async let fundNameTask = fundCode.isEmpty ? nil : platformClient.resolveAssetName(assetType: .fund, code: fundCode)
        async let stockNameTask = stockCode.isEmpty ? nil : platformClient.resolveAssetName(assetType: .stock, code: stockCode)
        let fundName = normalizedOptionalName(await fundNameTask)
        let stockName = normalizedOptionalName(await stockNameTask)

        switch (fundName, stockName) {
        case let (fundName?, nil):
            return PersonalAssetCodeResolution(assetType: .fund, code: fundCode, displayName: fundName, fundMarket: UserPortfolioHolding.detectFundMarket(from: fundCode))
        case let (nil, stockName?):
            return PersonalAssetCodeResolution(assetType: .stock, code: stockCode, displayName: stockName, stockMarket: manualStockMarket(assetType: .stock, codeText: rawCode))
        case let (fundName?, stockName?):
            if isLikelyStockCode(stockCode) {
                return PersonalAssetCodeResolution(assetType: .stock, code: stockCode, displayName: stockName, stockMarket: manualStockMarket(assetType: .stock, codeText: rawCode))
            }
            return PersonalAssetCodeResolution(assetType: .fund, code: fundCode, displayName: fundName, fundMarket: UserPortfolioHolding.detectFundMarket(from: fundCode))
        case (nil, nil):
            if isLikelyStockCode(stockCode) {
                return PersonalAssetCodeResolution(assetType: .stock, code: stockCode, displayName: nil, stockMarket: manualStockMarket(assetType: .stock, codeText: rawCode))
            }
            return PersonalAssetCodeResolution(assetType: .fund, code: fundCode, displayName: nil, fundMarket: UserPortfolioHolding.detectFundMarket(from: fundCode))
        }
    }

    @discardableResult
    func adjustPersonalAssetHoldingUnits(
        _ row: PersonalAssetAggregateRow,
        mode: PersonalAssetUnitAdjustmentMode,
        unitsText: String,
        unitNetValueText: String
    ) -> Bool {
        guard let units = decimalInputValue(unitsText), units > 0 else {
            errorMessage = "请输入大于 0 的份额。"
            return false
        }
        guard let unitNetValue = decimalInputValue(unitNetValueText), unitNetValue > 0 else {
            errorMessage = "请输入大于 0 的单位净值。"
            return false
        }
        guard let portfolioFileURL else {
            errorMessage = "应用数据目录还没准备好，暂时无法调整持仓份额。"
            return false
        }

        do {
            let existingHolding = row.rawHolding ?? row.holdingRow?.holding ?? (mode == .add ? row.archivedHolding : nil)
            let existingIndex = existingHolding.flatMap { holding in
                userPortfolioHoldings.firstIndex { $0.id == holding.id }
            }
            var nextHoldings = userPortfolioHoldings

            switch mode {
            case .add:
                if let existingHolding {
                    let oldUnits = existingHolding.units
                    let nextUnits = oldUnits + units
                    let existingCostPrice = existingHolding.costPrice ?? unitNetValue
                    let nextCostPrice = ((oldUnits * existingCostPrice) + (units * unitNetValue)) / nextUnits
                    let nextHolding = UserPortfolioHolding(
                        id: existingHolding.id,
                        fundCode: existingHolding.normalizedFundCode,
                        assetType: existingHolding.assetType,
                        units: nextUnits,
                        costPrice: normalizedCostPrice(nextCostPrice),
                        displayName: existingHolding.normalizedName ?? row.fundName,
                        stockMarket: existingHolding.stockMarket,
                        fundMarket: existingHolding.fundMarket,
                        isArchived: false,
                        archivedAt: nil
                    )
                    if let existingIndex {
                        nextHoldings[existingIndex] = nextHolding
                    } else {
                        nextHoldings.append(nextHolding)
                    }
                } else {
                    guard let fundCode = row.fundCode, !fundCode.isEmpty else {
                        errorMessage = "这个标的缺少代码，暂时无法新增持仓份额。"
                        return false
                    }
                    nextHoldings.append(
                        UserPortfolioHolding(
                            fundCode: fundCode,
                            assetType: row.assetType,
                            units: units,
                            costPrice: unitNetValue,
                            displayName: row.fundName,
                            stockMarket: row.detectedMarket,
                            fundMarket: row.detectedFundMarket
                        )
                    )
                }

            case .remove:
                guard let existingHolding, let existingIndex else {
                    errorMessage = "这个标的还没有已持有记录，无法删除份额。"
                    return false
                }
                guard units <= existingHolding.units + 0.0000001 else {
                    errorMessage = "删除份额不能超过当前份额 \(personalAssetDecimalText(existingHolding.units))。"
                    return false
                }

                let nextUnits = existingHolding.units - units
                if nextUnits <= 0.0000001 {
                    nextHoldings.remove(at: existingIndex)
                } else {
                    let nextCostPrice: Double?
                    if let costPrice = existingHolding.costPrice {
                        let nextCostValue = (existingHolding.units * costPrice) - (units * unitNetValue)
                        nextCostPrice = normalizedCostPrice(nextCostValue / nextUnits)
                    } else {
                        nextCostPrice = nil
                    }
                    nextHoldings[existingIndex] = UserPortfolioHolding(
                        id: existingHolding.id,
                        fundCode: existingHolding.normalizedFundCode,
                        assetType: existingHolding.assetType,
                        units: nextUnits,
                        costPrice: nextCostPrice,
                        displayName: existingHolding.normalizedName ?? row.fundName,
                        stockMarket: existingHolding.stockMarket,
                        fundMarket: existingHolding.fundMarket,
                        isArchived: false,
                        archivedAt: nil
                    )
                }
            }

            userPortfolioHoldings = nextHoldings
            userPortfolioSnapshot = nil
            clearCachedComputedProperties()
            if nextHoldings.isEmpty {
                try portfolioStore.delete(at: portfolioFileURL)
            } else {
                try portfolioStore.save(nextHoldings, to: portfolioFileURL)
            }

            let itemText = row.fundCode.map { "\(row.fundName)（\($0)）" } ?? row.fundName
            let actionText = mode == .add ? "添加" : "删除"
            noticeMessage = "已为 \(itemText) \(actionText) \(personalAssetDecimalText(units)) 份，单位净值 \(personalAssetDecimalText(unitNetValue))。"

            if !nextHoldings.isEmpty {
                Task { try? await refreshUserPortfolio(updateNotice: false) }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
        let holdings = activeUserPortfolioHoldings
        guard !holdings.isEmpty else {
            userPortfolioSnapshot = nil
            clearCachedComputedProperties()
            await refreshMarketIndicesIfNeeded()
            return
        }
        guard !isRefreshingPortfolio else { return }
        isRefreshingPortfolio = true
        defer { isRefreshingPortfolio = false }

        let snapshot = try await platformClient.fetchUserPortfolioSnapshot(holdings: holdings)
        userPortfolioSnapshot = snapshot
        clearCachedComputedProperties()
        if updateNotice {
            noticeMessage = "个人持仓估值已刷新。"
        }
        await refreshMarketIndicesIfNeeded()
    }

    func refreshMarketIndices(kinds requestedKinds: [MarketIndexKind]? = nil, updateNotice: Bool = true) async {
        let kinds = requestedKinds ?? selectedMenuBarMarketIndexKinds
        guard !kinds.isEmpty, !isRefreshingMarketIndices else { return }

        isRefreshingMarketIndices = true
        defer { isRefreshingMarketIndices = false }

        let quotes = await platformClient.fetchMarketIndexQuotes(kinds: kinds)
        if !quotes.isEmpty {
            marketIndexQuotes.merge(quotes) { _, new in new }
            if updateNotice {
                noticeMessage = "大盘行情已刷新。"
            }
        } else if updateNotice {
            errorMessage = "大盘行情暂时没有拉到可用数据。"
        }
    }

    func refreshMarketIndicesIfNeeded() async {
        guard menuBarTickerSettings.isEnabled, !selectedMenuBarMarketIndexKinds.isEmpty else { return }
        await refreshMarketIndices(updateNotice: false)
    }

    private var selectedMenuBarMarketIndexKinds: [MarketIndexKind] {
        var seen = Set<MarketIndexKind>()
        let selected = menuBarTickerSettings.enabledKinds.compactMap { kind -> MarketIndexKind? in
            guard let indexKind = kind.marketIndexRequest?.kind else { return nil }
            return seen.insert(indexKind).inserted ? indexKind : nil
        }
        return selected.sorted { left, right in
            let all = MarketIndexKind.allCases
            return (all.firstIndex(of: left) ?? 0) < (all.firstIndex(of: right) ?? 0)
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
                displayName: resolvedName,
                stockMarket: holding.stockMarket,
                fundMarket: holding.fundMarket,
                isArchived: holding.isArchived,
                archivedAt: holding.archivedAt
            )
        }

        guard resolvedCount > 0 else { return 0 }

        do {
            userPortfolioHoldings = enrichedHoldings
            clearCachedComputedProperties()
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

    func saveDraft(for target: PersonalDataImportTarget, mode: PersonalDataSaveMode = .merge) {
        switch target {
        case .holdings:
            savePortfolioFromDraft(mode: mode)
        case .pendingTrades:
            savePendingTradesFromDraft(mode: mode)
        case .investmentPlans:
            saveInvestmentPlansFromDraft(mode: mode)
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
            return hasAnyPortfolioRecords
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

    var activePortfolioHoldingCount: Int {
        activeUserPortfolioHoldings.count
    }

    var archivedPortfolioHoldingCount: Int {
        archivedUserPortfolioHoldings.count
    }

    var hasAnyPortfolioRecords: Bool {
        !userPortfolioHoldings.isEmpty
    }

    var hasPersonalPortfolio: Bool {
        !activeUserPortfolioHoldings.isEmpty
    }

    var hasArchivedPortfolio: Bool {
        !archivedUserPortfolioHoldings.isEmpty
    }

    var hasPendingTrades: Bool {
        !pendingTrades.isEmpty
    }

    var hasInvestmentPlans: Bool {
        !investmentPlans.isEmpty
    }

    var portfolioMenuBarTitle: String {
        if let menuBarTickerTitle {
            return menuBarTickerTitle
        }
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
        if hasInvestmentPlans {
            return "计划"
        }
        return hasArchivedPortfolio ? "归档" : "未配置"
    }

    var portfolioAutoRefreshStatusText: String {
        guard hasPersonalPortfolio else {
            if hasArchivedPortfolio {
                return "暂无活跃持仓，归档记录已保留"
            }
            return "导入持仓后自动刷新估值"
        }
        if isRefreshingPortfolio {
            return "持仓估值刷新中…"
        }
        return "持仓估值每 \(portfolioAutoRefreshIntervalSeconds) 秒自动刷新"
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

    private lazy var nativeClient = QiemanNativeClient(cookieFileURL: serverController.cookieFileURL)

    var monthlyPlatformSummary: [PlatformMonthSummary] {
        if let cached = _cachedMonthlyPlatformSummary { return cached }
        let actions = platformPayload?.actions ?? []
        var buckets: [String: (buy: Int, sell: Int, days: Set<String>)] = [:]

        for action in actions {
            let rawDate = action.txnDate ?? action.createdAt ?? ""
            guard rawDate.count >= 10 else { continue }
            guard let direction = platformActionDirection(action) else { continue }
            let month = String(rawDate.prefix(7))
            let day = String(rawDate.prefix(10))
            var bucket = buckets[month] ?? (0, 0, [])
            if direction == .buy {
                bucket.buy += 1
            } else {
                bucket.sell += 1
            }
            bucket.days.insert(day)
            buckets[month] = bucket
        }

        guard let latestMonth = buckets.keys.max() else {
            _cachedMonthlyPlatformSummary = []
            return []
        }

        let result = recentMonthKeys(endingAt: latestMonth, count: 12).map { month in
            let bucket = buckets[month] ?? (0, 0, [])
            return PlatformMonthSummary(
                month: month,
                totalCount: bucket.buy + bucket.sell,
                buyCount: bucket.buy,
                sellCount: bucket.sell,
                activeDays: bucket.days.count
            )
        }
        _cachedMonthlyPlatformSummary = result
        return result
    }

    private func recentMonthKeys(endingAt latestMonth: String, count: Int) -> [String] {
        guard let latestIndex = monthIndex(latestMonth) else { return [] }
        return (0..<count).compactMap { offset in
            monthKey(from: latestIndex - (count - 1 - offset))
        }
    }

    private func monthIndex(_ month: String) -> Int? {
        let parts = month.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let monthNumber = Int(parts[1]),
              (1...12).contains(monthNumber) else {
            return nil
        }
        return year * 12 + (monthNumber - 1)
    }

    private func monthKey(from index: Int) -> String? {
        guard index >= 0 else { return nil }
        let year = index / 12
        let month = index % 12 + 1
        return String(format: "%04d-%02d", year, month)
    }

    private enum PlatformActionDirection {
        case buy
        case sell
    }

    private func platformActionDirection(_ action: PlatformActionPayload) -> PlatformActionDirection? {
        let candidates = [
            action.side,
            action.action,
            action.actionTitle,
            action.title,
        ]
        for candidate in candidates {
            let value = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            guard !value.isEmpty else { continue }
            if value == "buy" || value.contains("买") || value.contains("申购") {
                return .buy
            }
            if value == "sell" || value.contains("卖") || value.contains("赎回") {
                return .sell
            }
        }
        return nil
    }

    var pendingTradeSummary: PersonalPendingTradeSummary? {
        if let cached = _cachedPendingTradeSummary { return cached }
        guard !pendingTrades.isEmpty else { _cachedPendingTradeSummary = nil; return nil }
        let totalCashAmount = pendingTrades.compactMap(\.amountValue).reduce(0, +)
        let cashTradeCount = pendingTrades.filter { $0.isCashTrade }.count
        let unitTradeCount = pendingTrades.filter { !$0.isCashTrade }.count
        let result = PersonalPendingTradeSummary(
            totalCashAmount: totalCashAmount,
            cashTradeCount: cashTradeCount,
            unitTradeCount: unitTradeCount,
            latestTime: pendingTrades.first?.occurredAt,
            actionCount: pendingTrades.count
        )
        _cachedPendingTradeSummary = result
        return result
    }

    var activeInvestmentPlans: [PersonalInvestmentPlan] {
        if let cached = _cachedActiveInvestmentPlans { return cached }
        let result = investmentPlans
            .filter(\.isActivePlan)
            .sorted(by: sortInvestmentPlans)
        _cachedActiveInvestmentPlans = result
        return result
    }

    var pausedInvestmentPlans: [PersonalInvestmentPlan] {
        if let cached = _cachedPausedInvestmentPlans { return cached }
        let result = investmentPlans
            .filter(\.isPausedPlan)
            .sorted(by: sortInvestmentPlans)
        _cachedPausedInvestmentPlans = result
        return result
    }

    var endedInvestmentPlans: [PersonalInvestmentPlan] {
        if let cached = _cachedEndedInvestmentPlans { return cached }
        let result = investmentPlans
            .filter(\.isEndedPlan)
            .sorted(by: sortInvestmentPlans)
        _cachedEndedInvestmentPlans = result
        return result
    }

    var investmentPlanSummary: PersonalInvestmentPlanSummary? {
        if let cached = _cachedInvestmentPlanSummary { return cached }
        guard !investmentPlans.isEmpty else { _cachedInvestmentPlanSummary = nil; return nil }
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

        let result = PersonalInvestmentPlanSummary(
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
        _cachedInvestmentPlanSummary = result
        return result
    }

    var personalAssetRows: [PersonalAssetAggregateRow] {
        if let cached = _cachedAssetRows { return cached }
        var valuationRowsByKey: [String: UserPortfolioValuationRow] = [:]
        for row in userPortfolioSnapshot?.rows ?? [] {
            valuationRowsByKey[personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName, market: row.holding.detectedMarket, fundMarket: row.holding.detectedFundMarket)] = row
        }

        var rawHoldingsByKey: [String: UserPortfolioHolding] = [:]
        for holding in activeUserPortfolioHoldings {
            let key = personalAssetKey(assetType: holding.assetType, code: holding.normalizedFundCode, name: holding.normalizedName, market: holding.detectedMarket, fundMarket: holding.detectedFundMarket)
            rawHoldingsByKey[key] = rawHoldingsByKey[key] ?? holding
        }

        var archivedHoldingsByKey: [String: UserPortfolioHolding] = [:]
        for holding in archivedUserPortfolioHoldings {
            let key = personalAssetKey(assetType: holding.assetType, code: holding.normalizedFundCode, name: holding.normalizedName, market: holding.detectedMarket, fundMarket: holding.detectedFundMarket)
            archivedHoldingsByKey[key] = archivedHoldingsByKey[key] ?? holding
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
            .union(archivedHoldingsByKey.keys)
            .union(pendingByKey.keys)
            .union(plansByKey.keys)

        let result = keys
            .map { key in
                let holdingRow = valuationRowsByKey[key]
                let rawHolding = rawHoldingsByKey[key]
                let archivedHolding = archivedHoldingsByKey[key]
                let pending = (pendingByKey[key] ?? []).sorted { $0.occurredAt > $1.occurredAt }
                let plans = (plansByKey[key] ?? []).sorted(by: sortInvestmentPlans)
                let assetType = holdingRow?.holding.assetType
                    ?? rawHolding?.assetType
                    ?? archivedHolding?.assetType
                    ?? .fund
                let fundName = holdingRow?.fundName
                    ?? rawHolding?.normalizedName
                    ?? archivedHolding?.normalizedName
                    ?? pending.first?.fundName
                    ?? plans.first?.fundName
                    ?? "未命名标的"
                let fundCode = holdingRow?.holding.normalizedFundCode
                    ?? rawHolding?.normalizedFundCode
                    ?? archivedHolding?.normalizedFundCode
                    ?? pending.first?.fundCode
                    ?? plans.first?.fundCode

                return PersonalAssetAggregateRow(
                    key: key,
                    assetType: assetType,
                    fundName: fundName,
                    fundCode: normalizedCode(fundCode),
                    holdingRow: holdingRow,
                    rawHolding: rawHolding,
                    archivedHolding: archivedHolding,
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
        _cachedAssetRows = result
        _cachedAssetSummary = nil
        return result
    }

    var personalAssetSummary: PersonalAssetAggregateSummary? {
        if let cached = _cachedAssetSummary { return cached }
        let rows = personalAssetRows
        guard !rows.isEmpty else { _cachedAssetSummary = nil; return nil }
        var holdingFundCount = 0
        var pendingFundCount = 0
        var activePlanFundCount = 0
        var totalMarketValue = 0.0
        var totalPendingCashAmount = 0.0
        var totalActivePlanCount = 0
        var totalPausedPlanCount = 0
        var totalEndedPlanCount = 0
        var totalCumulativePlanAmount = 0.0
        var totalEstimatedNextPlanAmount = 0.0
        var totalEffectiveHoldingAmount = 0.0

        for row in rows {
            if row.hasHolding {
                holdingFundCount += 1
            }
            if row.hasPending {
                pendingFundCount += 1
            }
            if row.activePlanCount > 0 {
                activePlanFundCount += 1
            }
            totalMarketValue += row.marketValue ?? 0
            totalPendingCashAmount += row.pendingCashAmount
            totalActivePlanCount += row.activePlanCount
            totalPausedPlanCount += row.pausedPlanCount
            totalEndedPlanCount += row.endedPlanCount
            totalCumulativePlanAmount += row.totalCumulativePlanAmount
            totalEstimatedNextPlanAmount += row.estimatedNextPlanAmount
            totalEffectiveHoldingAmount += row.effectiveHoldingAmount
        }

        let result = PersonalAssetAggregateSummary(
            fundCount: rows.count,
            holdingFundCount: holdingFundCount,
            pendingFundCount: pendingFundCount,
            activePlanFundCount: activePlanFundCount,
            totalMarketValue: totalMarketValue,
            totalPendingCashAmount: totalPendingCashAmount,
            totalActivePlanCount: totalActivePlanCount,
            totalPausedPlanCount: totalPausedPlanCount,
            totalEndedPlanCount: totalEndedPlanCount,
            totalCumulativePlanAmount: totalCumulativePlanAmount,
            totalEstimatedNextPlanAmount: totalEstimatedNextPlanAmount,
            totalEffectiveHoldingAmount: totalEffectiveHoldingAmount
        )
        _cachedAssetSummary = result
        return result
    }

    private var outputDirectoryURL: URL? {
        dataDirectoryURL?.appendingPathComponent("output", isDirectory: true)
    }

    private var activeUserPortfolioHoldings: [UserPortfolioHolding] {
        userPortfolioHoldings.filter { !$0.isArchived }
    }

    private var archivedUserPortfolioHoldings: [UserPortfolioHolding] {
        userPortfolioHoldings.filter(\.isArchived)
    }

    private func loadSavedPortfolio() {
        guard let portfolioFileURL else { return }
        do {
            let holdings = try portfolioStore.load(from: portfolioFileURL)
            userPortfolioHoldings = holdings
            clearCachedComputedProperties()
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
            clearCachedComputedProperties()
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
            clearCachedComputedProperties()
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

    private func restartPortfolioAutoRefreshLoop() {
        portfolioAutoRefreshTask?.cancel()
        let interval = portfolioAutoRefreshIntervalSeconds * 1_000_000_000
        portfolioAutoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self?.refreshPortfolioIfAutoRefreshVisible()
            }
        }
    }

    private func refreshPortfolioIfAutoRefreshVisible() async {
        guard hasPersonalPortfolio, !isRefreshingPortfolio else {
            await refreshMarketIndicesIfNeeded()
            return
        }
        guard selectedSection == .portfolio || selectedSection == .overview || menuBarTickerSettings.isEnabled else {
            await refreshMarketIndicesIfNeeded()
            return
        }

        do {
            try await refreshUserPortfolio(updateNotice: false)
        } catch {
            if selectedSection == .portfolio {
                errorMessage = "个人持仓自动刷新失败：\(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func applyPersonalAssetAutomation(updateNotice: Bool = true) async -> Bool {
        guard dataDirectoryURL != nil, !isApplyingPersonalAssetAutomation else { return false }
        isApplyingPersonalAssetAutomation = true
        defer { isApplyingPersonalAssetAutomation = false }

        let today = Date()
        let costDeviationByFundKey = latestCostDeviationPctByFundKey()
        let planResult = personalAssetAutomation.generateDuePlanTrades(
            plans: investmentPlans,
            existingPendingTrades: pendingTrades,
            today: today
        ) { [weak self, costDeviationByFundKey] plan, _ in
            self?.estimatedAutomationAmount(for: plan, costDeviationByFundKey: costDeviationByFundKey)
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
            if holdingsChanged || pendingChanged || plansChanged {
                clearCachedComputedProperties()
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        if holdingsChanged, !activeUserPortfolioHoldings.isEmpty {
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
            let key = personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName, market: row.holding.detectedMarket, fundMarket: row.holding.detectedFundMarket)
            if let price = row.resolvedPrice, price > 0 {
                priceByKey[key] = price
            }
        }

        for holding in holdings {
            let key = personalAssetKey(assetType: holding.assetType, code: holding.normalizedFundCode, name: holding.normalizedName, market: holding.detectedMarket, fundMarket: holding.detectedFundMarket)
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
                let key = personalAssetKey(assetType: row.holding.assetType, code: row.holding.normalizedFundCode, name: row.fundName, market: row.holding.detectedMarket, fundMarket: row.holding.detectedFundMarket)
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

    private func estimatedAutomationAmount(for plan: PersonalInvestmentPlan, costDeviationByFundKey: [String: Double]) -> Double? {
        guard plan.normalizedAmountBounds.min != nil else { return nil }
        let key = personalFundKey(code: plan.fundCode, name: plan.fundName)
        return plan.estimatedExecutionAmount(costDeviationPct: costDeviationByFundKey[key])
    }

    private func latestCostDeviationPctByFundKey() -> [String: Double] {
        var values: [String: Double] = [:]
        for row in userPortfolioSnapshot?.rows ?? [] {
            guard row.holding.assetType == .fund else { continue }
            let key = personalFundKey(code: row.holding.normalizedFundCode, name: row.fundName)
            values[key] = PersonalInvestmentPlan.drawdownCostDeviationPct(
                currentPrice: row.resolvedPrice,
                costPrice: row.holding.costPrice
            )
        }
        return values
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

    private func importedPortfolioHoldings(from text: String) throws -> [UserPortfolioHolding] {
        if shouldUsePortfolioSummaryImport(for: text) {
            let outputURL = temporaryJSONURL(prefix: "qieman-holdings-import")
            defer { try? FileManager.default.removeItem(at: outputURL) }
            try runPortfolioSummaryImport(text: text, outputURL: outputURL)
            return try portfolioStore.load(from: outputURL)
        }
        return try portfolioStore.parseDraft(text)
    }

    private func importedPendingTrades(from text: String) throws -> [PersonalPendingTrade] {
        let outputURL = temporaryJSONURL(prefix: "qieman-pending-import")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try runTextImportScript(
            scriptRelativePath: "scripts/import_alipay_pending_trades.py",
            text: text,
            additionalArguments: ["--output", outputURL.path]
        )
        return try pendingTradesStore.load(from: outputURL)
    }

    private func importedInvestmentPlans(from text: String) throws -> [PersonalInvestmentPlan] {
        let outputURL = temporaryJSONURL(prefix: "qieman-plan-import")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try runTextImportScript(
            scriptRelativePath: "scripts/import_alipay_investment_plans.py",
            text: text,
            additionalArguments: ["--output", outputURL.path]
        )
        return try investmentPlansStore.load(from: outputURL)
    }

    private func runPortfolioSummaryImport(text: String, outputURL: URL) throws {
        try runTextImportScript(
            scriptRelativePath: "scripts/import_alipay_portfolio.py",
            text: text,
            additionalArguments: ["--output", outputURL.path]
        )
    }

    @discardableResult
    private func runTextImportScript(scriptRelativePath: String, text: String, additionalArguments: [String] = []) throws -> String {
        _ = try serverController.prepareEnvironment()
        guard let projectDirectory = serverController.projectDirectory else {
            throw LocalServerError.projectMissing
        }
        let inputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qieman-import-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: inputURL) }
        try text.write(to: inputURL, atomically: true, encoding: .utf8)
        return try runPythonScript(
            projectDirectory: projectDirectory,
            scriptRelativePath: scriptRelativePath,
            arguments: ["--input", inputURL.path] + additionalArguments
        )
    }

    private func temporaryJSONURL(prefix: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
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

    func showMainWindow(section: AppSection) {
        selectedSection = section
        revealMainWindowIfNeeded()
    }

    private func revealMainWindowIfNeeded() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { window in
            window.canBecomeMain && !(window is NSPanel)
        }) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        _ = NSApplication.shared.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
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
                _cachedMonthlyPlatformSummary = nil
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
                ensureSelectedForumPost(preferredID: payload.targetID)
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

    private func replacingInvestmentPlan(_ plan: PersonalInvestmentPlan, status: String) -> PersonalInvestmentPlan {
        PersonalInvestmentPlan(
            id: plan.id,
            planTypeLabel: plan.planTypeLabel,
            fundName: plan.fundName,
            fundCode: plan.fundCode,
            scheduleText: plan.scheduleText,
            amountText: plan.amountText,
            minAmount: plan.minAmount,
            maxAmount: plan.maxAmount,
            investedPeriods: plan.investedPeriods,
            cumulativeInvestedAmount: plan.cumulativeInvestedAmount,
            paymentMethod: plan.paymentMethod,
            nextExecutionDate: plan.nextExecutionDate,
            status: normalizedInvestmentPlanStatus(status),
            note: plan.note
        )
    }

    private func normalizedInvestmentPlanStatus(_ value: String) -> String {
        if value.contains("终止") {
            return "已终止"
        }
        if value.contains("暂停") {
            return "已暂停"
        }
        return "进行中"
    }

    private func validatedPendingTrade(
        id: UUID,
        occurredAt: String,
        actionLabel: String,
        fundName: String,
        fundCode: String,
        targetFundName: String,
        targetFundCode: String,
        amountText: String,
        status: String,
        note: String
    ) -> PersonalPendingTrade? {
        let trimmedOccurredAt = occurredAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAction = actionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFundName = fundName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFundCode = normalizedCode(fundCode)
        let trimmedTargetName = targetFundName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTargetCode = normalizedCode(targetFundCode)
        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAction.isEmpty else {
            errorMessage = "请输入交易动作。"
            return nil
        }
        guard !trimmedFundName.isEmpty || normalizedFundCode != nil else {
            errorMessage = "请输入基金名称或基金代码。"
            return nil
        }
        guard let amount = normalizedPendingAmount(from: amountText) else {
            errorMessage = "请输入大于 0 的金额或份额，例如 10元 或 100份。"
            return nil
        }

        return PersonalPendingTrade(
            id: id,
            occurredAt: trimmedOccurredAt.isEmpty ? Self.timestampString() : trimmedOccurredAt,
            actionLabel: trimmedAction,
            fundName: trimmedFundName.isEmpty ? (normalizedFundCode ?? "未命名标的") : trimmedFundName,
            targetFundName: trimmedTargetName.isEmpty ? nil : trimmedTargetName,
            fundCode: normalizedFundCode,
            targetFundCode: normalizedTargetCode,
            amountText: amount.text,
            amountValue: amount.cash,
            unitValue: amount.units,
            status: trimmedStatus.isEmpty ? "交易进行中" : trimmedStatus,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
    }

    private func normalizedPendingAmount(from text: String) -> (text: String, cash: Double?, units: Double?)? {
        let trimmed = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix("份") {
            guard let value = decimalInputValue(trimmed), value > 0 else { return nil }
            return ("\(personalAssetDecimalText(value))份", nil, value)
        }

        let cashText = trimmed.hasSuffix("元") ? String(trimmed.dropLast()) : trimmed
        guard let value = decimalInputValue(cashText), value > 0 else { return nil }
        return ("\(personalAssetDecimalText(value))元", value, nil)
    }

    private func validatedInvestmentPlan(
        id: UUID,
        planTypeLabel: String,
        fundName: String,
        fundCode: String,
        scheduleText: String,
        amountText: String,
        investedPeriodsText: String,
        cumulativeInvestedAmountText: String,
        paymentMethod: String,
        nextExecutionDate: String,
        status: String,
        note: String
    ) -> PersonalInvestmentPlan? {
        let trimmedPlanType = planTypeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFundName = fundName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFundCode = normalizedCode(fundCode)
        let trimmedSchedule = scheduleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPayment = paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNextExecutionDate = nextExecutionDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStatus = normalizedInvestmentPlanStatus(status)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPlanType.isEmpty else {
            errorMessage = "请输入计划类型。"
            return nil
        }
        guard !trimmedFundName.isEmpty || normalizedFundCode != nil else {
            errorMessage = "请输入基金名称或基金代码。"
            return nil
        }
        guard !trimmedSchedule.isEmpty else {
            errorMessage = "请输入定投周期或计划说明。"
            return nil
        }

        let amountBounds = investmentPlanAmountBounds(from: trimmedAmount)
        guard let minAmount = amountBounds.min, minAmount > 0 else {
            errorMessage = "请输入大于 0 的定投金额。"
            return nil
        }
        if let maxAmount = amountBounds.max, maxAmount <= 0 {
            errorMessage = "定投金额上限需要大于 0。"
            return nil
        }
        if normalizedStatus == "进行中", trimmedNextExecutionDate.isEmpty {
            errorMessage = "进行中的定投计划需要填写下次执行时间。"
            return nil
        }

        let investedPeriods: Int?
        let trimmedPeriods = investedPeriodsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPeriods.isEmpty {
            investedPeriods = nil
        } else if let parsed = Int(trimmedPeriods), parsed >= 0 {
            investedPeriods = parsed
        } else {
            errorMessage = "已投期数需要是大于等于 0 的整数。"
            return nil
        }

        let cumulativeAmount: Double?
        let trimmedCumulative = cumulativeInvestedAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCumulative.isEmpty {
            cumulativeAmount = nil
        } else if let parsed = decimalInputValue(trimmedCumulative), parsed >= 0 {
            cumulativeAmount = parsed
        } else {
            errorMessage = "累计投入需要是大于等于 0 的金额。"
            return nil
        }

        return PersonalInvestmentPlan(
            id: id,
            planTypeLabel: trimmedPlanType,
            fundName: trimmedFundName.isEmpty ? (normalizedFundCode ?? "未命名标的") : trimmedFundName,
            fundCode: normalizedFundCode,
            scheduleText: trimmedSchedule,
            amountText: normalizedInvestmentPlanAmountText(trimmedAmount, bounds: amountBounds),
            minAmount: minAmount,
            maxAmount: amountBounds.max ?? minAmount,
            investedPeriods: investedPeriods,
            cumulativeInvestedAmount: cumulativeAmount,
            paymentMethod: trimmedPayment.isEmpty ? nil : trimmedPayment,
            nextExecutionDate: trimmedNextExecutionDate,
            status: normalizedStatus,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
    }

    private func investmentPlanAmountBounds(from text: String) -> (min: Double?, max: Double?) {
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "—", with: "~")
            .replacingOccurrences(of: "－", with: "~")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = normalized
            .split { !"0123456789.".contains($0) }
            .compactMap { Double($0) }
        guard let first = numbers.first else {
            return (nil, nil)
        }
        if numbers.count >= 2, let second = numbers.dropFirst().first {
            return first <= second ? (first, second) : (second, first)
        }
        return (first, first)
    }

    private func normalizedInvestmentPlanAmountText(_ text: String, bounds: (min: Double?, max: Double?)) -> String {
        if text.contains("元") {
            return text
        }
        guard let minAmount = bounds.min else {
            return text
        }
        let maxAmount = bounds.max ?? minAmount
        if abs(maxAmount - minAmount) < 0.001 {
            return "\(personalAssetDecimalText(minAmount))元"
        }
        return "\(personalAssetDecimalText(minAmount))~\(personalAssetDecimalText(maxAmount))元"
    }

    private func personalFundKey(code: String?, name: String?, market: StockMarket? = nil, fundMarket: FundMarket? = nil) -> String {
        personalAssetKey(assetType: .fund, code: code, name: name, market: market, fundMarket: fundMarket)
    }

    private func personalAssetKey(assetType: PersonalAssetType, code: String?, name: String?, market: StockMarket? = nil, fundMarket: FundMarket? = nil) -> String {
        if let code = normalizedCode(code) {
            let marketSegment: String
            if assetType == .stock {
                marketSegment = ":mkt:\(market?.rawValue ?? "a")"
            } else {
                marketSegment = ":fundmkt:\((fundMarket ?? UserPortfolioHolding.detectFundMarket(from: code)).rawValue)"
            }
            return "\(assetType.rawValue)\(marketSegment):code:\(code)"
        }
        let normalizedName = (name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
        let marketSegment: String
        if assetType == .stock {
            marketSegment = ":mkt:\(market?.rawValue ?? "a")"
        } else {
            marketSegment = ":fundmkt:\((fundMarket ?? .offExchange).rawValue)"
        }
        return "\(assetType.rawValue)\(marketSegment):name:\(normalizedName)"
    }

    private func normalizedCode(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedManualAssetRawCode(_ codeText: String) -> String {
        codeText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
    }

    private func normalizedManualAssetCode(assetType: PersonalAssetType, codeText: String) -> String {
        let trimmed = normalizedManualAssetRawCode(codeText)
        guard assetType == .stock else {
            return UserPortfolioHolding.normalizedFundCode(from: trimmed)
        }

        let upper = trimmed.uppercased()
        if upper.hasPrefix("HK:") {
            return normalizedHongKongStockCode(String(upper.dropFirst(3)))
        }
        if upper.hasPrefix("US:") {
            return String(upper.dropFirst(3))
        }
        if upper.hasPrefix("HK"), upper.count > 2 {
            let raw = String(upper.dropFirst(2))
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: raw)) {
                return normalizedHongKongStockCode(raw)
            }
        }
        if upper.count == 8,
           (upper.hasPrefix("SH") || upper.hasPrefix("SZ") || upper.hasPrefix("BJ")),
           CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: String(upper.dropFirst(2)))) {
            return String(upper.dropFirst(2))
        }
        if upper.count == 9,
           (upper.hasSuffix(".SH") || upper.hasSuffix(".SZ") || upper.hasSuffix(".BJ")),
           CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: String(upper.prefix(6)))) {
            return String(upper.prefix(6))
        }
        return trimmed
    }

    private func hasExplicitStockMarket(_ codeText: String) -> Bool {
        let upper = normalizedManualAssetRawCode(codeText).uppercased()
        return upper.hasPrefix("SH")
            || upper.hasPrefix("SZ")
            || upper.hasPrefix("BJ")
            || upper.hasPrefix("HK:")
            || upper.hasPrefix("US:")
            || upper.hasSuffix(".SH")
            || upper.hasSuffix(".SZ")
            || upper.hasSuffix(".BJ")
    }

    private func hasExplicitFundMarket(_ codeText: String) -> Bool {
        let upper = normalizedManualAssetRawCode(codeText).uppercased()
        return upper.hasPrefix("ETF:")
            || upper.hasPrefix("LOF:")
            || upper.hasPrefix("EX:")
            || upper.hasPrefix("FUND:")
            || upper.hasPrefix("OTC:")
    }

    private func manualStockMarket(assetType: PersonalAssetType, codeText: String) -> StockMarket? {
        guard assetType == .stock else { return nil }
        return UserPortfolioHolding.detectStockMarket(from: normalizedManualAssetRawCode(codeText))
            ?? UserPortfolioHolding.detectStockMarket(from: normalizedManualAssetCode(assetType: assetType, codeText: codeText))
    }

    private func normalizedHongKongStockCode(_ value: String) -> String {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.allSatisfy(\.isNumber), code.count < 5 else {
            return code
        }
        return String(repeating: "0", count: 5 - code.count) + code
    }

    private func manualFundMarket(assetType: PersonalAssetType, codeText: String) -> FundMarket? {
        guard assetType == .fund else { return nil }
        let upper = normalizedManualAssetRawCode(codeText).uppercased()
        if upper.hasPrefix("ETF:") || upper.hasPrefix("LOF:") || upper.hasPrefix("EX:") {
            return .onExchange
        }
        if upper.hasPrefix("FUND:") || upper.hasPrefix("OTC:") {
            return .offExchange
        }
        return UserPortfolioHolding.detectFundMarket(from: normalizedManualAssetCode(assetType: .fund, codeText: codeText))
    }

    private func isLikelyStockCode(_ code: String) -> Bool {
        let value = normalizedManualAssetRawCode(code)
        guard value.count == 6, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: value)) else {
            return false
        }
        return value.hasPrefix("00")
            || value.hasPrefix("30")
            || value.hasPrefix("60")
            || value.hasPrefix("68")
            || value.hasPrefix("90")
            || value.hasPrefix("20")
            || value.hasPrefix("43")
            || value.hasPrefix("83")
            || value.hasPrefix("87")
            || value.hasPrefix("88")
            || value.hasPrefix("92")
    }

    private func normalizedOptionalName(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func decimalInputValue(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "份", with: "")
            .replacingOccurrences(of: "元", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private func normalizedCostPrice(_ value: Double) -> Double {
        abs(value) < 0.0000001 ? 0 : value
    }

    private func timestampNow() -> String {
        Self.isoTimestampFormatter.string(from: Date())
    }

    private func personalAssetDecimalText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let isoTimestampFormatter = ISO8601DateFormatter()

    private static func timestampString() -> String {
        timestampFormatter.string(from: Date())
    }
}
