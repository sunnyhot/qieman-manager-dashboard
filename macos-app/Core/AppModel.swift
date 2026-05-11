import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement
import SwiftUI

// MARK: - Settings

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

struct LiveRefreshError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - AppModel

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
    @Published var showsInDock: Bool = (UserDefaults.standard.object(forKey: "qieman.dashboard.showsInDock") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(showsInDock, forKey: "qieman.dashboard.showsInDock")
            NSApplication.shared.setActivationPolicy(showsInDock ? .regular : .accessory)
        }
    }

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

    @Published var baseURL: URL?
    @Published var logFileURL: URL?
    @Published var dataDirectoryURL: URL?

    // Services
    let serverController = LocalServerController()
    let platformClient = QiemanPlatformNativeClient()
    let portfolioStore = UserPortfolioStore()
    let pendingTradesStore = PendingTradesStore()
    let investmentPlansStore = InvestmentPlansStore()
    let managerWatchStore = ManagerWatchStore()
    let importRecognizer = PersonalImportRecognizer()
    let notificationManager = LocalNotificationManager()
    let personalAssetAutomation = PersonalAssetAutomation()
    let updateAutoCheckDefaultsKey = "qieman.dashboard.update.lastAutoCheckAt"
    let updateAutoCheckInterval: TimeInterval = 12 * 60 * 60
    let portfolioAutoRefreshIntervalSeconds: UInt64 = 60

    // Runtime state
    var didApplyDefaultForm = false
    private var didStart = false
    var managerWatchTask: Task<Void, Never>?
    var personalAssetAutomationTask: Task<Void, Never>?
    var portfolioAutoRefreshTask: Task<Void, Never>?
    var activeCommentsRequestKey = ""
    var isApplyingPersonalAssetAutomation = false
    private var cancellables = Set<AnyCancellable>()

    // Lazy native client backing store
    var _nativeClient: QiemanNativeClient?
    var _nativeClientInitialized = false

    // Cached computed property backing stores
    var _cachedAssetRows: [PersonalAssetAggregateRow]?
    var _cachedAssetSummary: PersonalAssetAggregateSummary?
    var _cachedMonthlyPlatformSummary: [PlatformMonthSummary]?
    var _cachedActiveInvestmentPlans: [PersonalInvestmentPlan]?
    var _cachedPausedInvestmentPlans: [PersonalInvestmentPlan]?
    var _cachedEndedInvestmentPlans: [PersonalInvestmentPlan]?
    var _cachedInvestmentPlanSummary: PersonalInvestmentPlanSummary?
    var _cachedPendingTradeSummary: PersonalPendingTradeSummary?

    func clearCachedComputedProperties() {
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
}
