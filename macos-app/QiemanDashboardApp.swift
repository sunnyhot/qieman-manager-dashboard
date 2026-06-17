import AppKit
import Combine
import SwiftUI
import UserNotifications

enum AppLaunchPresentationPolicy {
    static func initialActivationPolicy(storedShowsInDock: Bool) -> NSApplication.ActivationPolicy {
        // Keep the first interactive launch regular so SwiftUI can create the
        // initial WindowGroup even when the saved preference hides the Dock icon.
        .regular
    }

    static func configuredActivationPolicy(showsInDock: Bool) -> NSApplication.ActivationPolicy {
        showsInDock ? .regular : .accessory
    }
}

enum AppRuntimeCapabilities {
    static func shouldInstallNotificationDelegateAtLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["QIEMAN_INSTALL_NOTIFICATION_DELEGATE_AT_LAUNCH"] == "1"
    }
}

enum AppLaunchWindowPolicy {
    static func shouldShowFallbackMainWindow(
        hasTrackedVisibleMainWindow: Bool,
        hasVisibleMainWindow: Bool
    ) -> Bool {
        !hasTrackedVisibleMainWindow && !hasVisibleMainWindow
    }
}

final class QiemanApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private enum MenuBarRenderState: Equatable {
        case fallback(title: String)
        case ticker(entries: [MenuBarTickerEntry], appearance: MenuBarTickerAppearance, page: Int, totalPages: Int, barHeight: CGFloat)
    }

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: AppModel?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    /// Local monitor for double-click events in the titlebar/toolbar area.
    private var titlebarDoubleClickMonitor: Any?
    private var didConfigure = false
    private var carouselPageIndex = 0
    private var carouselTimer: Timer?
    private var lastEntryIDs: [String] = []
    private var lastMenuBarRenderState: MenuBarRenderState?
    private var didFinishLaunching = false
    /// Retains a reference to the main window so it can be re-shown after closing.
    /// Set by both the SwiftUI WindowGroup (onAppear) and createMainWindow().
    fileprivate(set) var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let telemetryStart = PerformanceTelemetry.start()
        defer {
            PerformanceTelemetry.record(
                "app.delegate.finishLaunching",
                startedAt: telemetryStart
            )
        }

        if AppRuntimeCapabilities.shouldInstallNotificationDelegateAtLaunch() {
            UNUserNotificationCenter.current().delegate = self
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.image = nil
        button.action = #selector(togglePopover)
        button.target = self

        popover = NSPopover()
        popover.contentSize = NSSize(width: 392, height: 720)
        popover.behavior = .transient

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.popover.isShown {
                if event.window != self.popover.contentViewController?.view.window {
                    self.popover.performClose(nil)
                }
            }
        }

        let showInDock = (UserDefaults.standard.object(forKey: "qieman.dashboard.showsInDock") as? Bool) ?? true
        NSApplication.shared.setActivationPolicy(
            AppLaunchPresentationPolicy.initialActivationPolicy(storedShowsInDock: showInDock)
        )

        // Install local monitor to handle double-click in the titlebar/toolbar area.
        // SwiftUI's .onTapGesture cannot reach the native macOS titlebar region when
        // using hiddenTitleBar + titlebarAppearsTransparent, so we intercept at AppKit level.
        titlebarDoubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleTitlebarDoubleClick(event) ?? event
        }

        didFinishLaunching = true
        Task { @MainActor [weak self] in
            self?.configure(model: QiemanAppModelHolder.shared)
        }
    }

    func configure(model: AppModel) {
        self.model = model
        guard didFinishLaunching else { return }
        guard !didConfigure else { return }
        didConfigure = true
        let telemetryStart = PerformanceTelemetry.start()
        defer {
            PerformanceTelemetry.record(
                "app.delegate.configure",
                startedAt: telemetryStart
            )
        }
        Task { @MainActor in
            model.appDelegate = self
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            NSApplication.shared.setActivationPolicy(
                AppLaunchPresentationPolicy.configuredActivationPolicy(showsInDock: model.showsInDock)
            )
            let view = MenuBarPortfolioView()
                .environmentObject(model)
            self.popover.contentViewController = NSHostingController(rootView: view)
            self.updateTitle()

            model.objectWillChange
                .receive(on: RunLoop.main)
                .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.updateTitle()
                    }
                }
                .store(in: &self.cancellables)

            // Sync NSAppearance on all windows when the user changes appearance setting.
            // .preferredColorScheme() only affects SwiftUI's Environment; NSColor dynamic
            // colors (used by AppPalette.adaptive) depend on the window's NSAppearance.
            NotificationCenter.default.publisher(for: .qiemanAppearanceDidChange)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.syncWindowAppearances()
                    }
                }
                .store(in: &self.cancellables)
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            let hasTrackedVisibleMainWindow = self.mainWindow?.isVisible == true
            let hasVisibleMainWindow = NSApplication.shared.windows.contains { window in
                window.isVisible && window.canBecomeMain && !(window is NSPanel)
            }
            guard AppLaunchWindowPolicy.shouldShowFallbackMainWindow(
                hasTrackedVisibleMainWindow: hasTrackedVisibleMainWindow,
                hasVisibleMainWindow: hasVisibleMainWindow
            ) else { return }
            self.showMainWindow()
        }
    }

    /// Apply the current appearance setting to every open NSWindow, NSHostingView,
    /// and the popover — so both NSColor dynamic colors and SwiftUI's
    /// .preferredColorScheme() stay in sync.
    @MainActor private func syncWindowAppearances() {
        guard let model else { return }
        let target = model.appearance.nsAppearance
        for window in NSApplication.shared.windows {
            window.appearance = target
            // Walk the view hierarchy to find NSHostingView instances and
            // explicitly set their appearance so SwiftUI picks up the change.
            setAppearanceRecursively(in: window.contentView, to: target)
        }
        // Also update the popover's hosting controller
        if let popoverVC = popover.contentViewController {
            setAppearanceRecursively(in: popoverVC.view, to: target)
        }
    }

    /// Walk an NSView hierarchy and set appearance on all NSHostingView instances.
    @MainActor private func setAppearanceRecursively(in view: NSView?, to appearance: NSAppearance?) {
        guard let view else { return }
        if String(describing: type(of: view)).contains("NSHostingView") {
            view.appearance = appearance
        }
        for subview in view.subviews {
            setAppearanceRecursively(in: subview, to: appearance)
        }
    }

    @MainActor private func updateTitle() {
        guard let model, let button = statusItem.button else { return }
        let telemetryStart = PerformanceTelemetry.start()
        var renderedEntryCount = 0
        defer {
            PerformanceTelemetry.record(
                "menuBar.title.render",
                startedAt: telemetryStart,
                metadata: [
                    "entryCount": "\(renderedEntryCount)",
                    "enabled": "\(model.menuBarTickerSettings.isEnabled)"
                ]
            )
        }
        let allEntries = model.menuBarTickerAllCandidates
        let settings = model.menuBarTickerSettings.normalized()
        let appearance = settings.appearance.normalized()
        let pageSize = settings.maxVisibleItems

        // Reset page if entries changed
        let currentIDs = allEntries.map(\.id)
        if currentIDs != lastEntryIDs {
            lastEntryIDs = currentIDs
            carouselPageIndex = 0
            lastMenuBarRenderState = nil
        }

        let barHeight = NSStatusBar.system.thickness

        if allEntries.isEmpty {
            stopCarousel()
            let fallbackTitle = model.portfolioMenuBarFallbackTitle
            let state = MenuBarRenderState.fallback(title: fallbackTitle)
            guard state != lastMenuBarRenderState else { return }
            lastMenuBarRenderState = state

            let icon = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "QiemanDashboard") ?? NSImage()
            icon.isTemplate = true
            button.image = icon
            button.toolTip = fallbackTitle
            button.needsDisplay = true
            statusItem.length = NSStatusItem.squareLength
            return
        }

        // Paginate entries
        let totalPages = Int(ceil(Double(allEntries.count) / Double(pageSize)))
        if totalPages <= 1 {
            stopCarousel()
            carouselPageIndex = 0
        }
        let safePage = min(carouselPageIndex, max(0, totalPages - 1))
        let start = safePage * pageSize
        let end = min(start + pageSize, allEntries.count)
        let displayEntries = Array(allEntries[start..<end])
        renderedEntryCount = displayEntries.count

        // Start or update the carousel timer before the render guard so interval-only
        // settings changes still take effect without forcing a redraw.
        if totalPages > 1 {
            startCarousel(interval: settings.carouselIntervalSeconds)
        }

        let state = MenuBarRenderState.ticker(
            entries: displayEntries,
            appearance: appearance,
            page: safePage,
            totalPages: totalPages,
            barHeight: barHeight
        )
        guard state != lastMenuBarRenderState else { return }
        lastMenuBarRenderState = state

        let lines = displayEntries.map { $0.compactText }
        let image = renderTickerImage(entries: displayEntries, appearance: appearance, barHeight: barHeight)
        button.image = image
        let pageIndicator = totalPages > 1 ? " [\((safePage + 1))/\(totalPages)]" : ""
        button.toolTip = lines.joined(separator: "  ") + pageIndicator
        button.needsDisplay = true
        statusItem.length = image.size.width
    }

    private func startCarousel(interval: Double) {
        let clamped = max(MenuBarTickerSettings.minCarouselInterval, min(interval, MenuBarTickerSettings.maxCarouselInterval))
        if let existing = carouselTimer {
            if abs(existing.timeInterval - clamped) < 0.01 {
                return
            }
            existing.invalidate()
            carouselTimer = nil
        }
        carouselTimer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.advanceCarousel()
            }
        }
    }

    private func stopCarousel() {
        carouselTimer?.invalidate()
        carouselTimer = nil
    }

    @MainActor private func advanceCarousel() {
        guard let model else { return }
        let allEntries = model.menuBarTickerAllCandidates
        let pageSize = model.menuBarTickerSettings.maxVisibleItems
        let totalPages = Int(ceil(Double(allEntries.count) / Double(pageSize)))
        guard totalPages > 1 else {
            stopCarousel()
            return
        }
        carouselPageIndex = (carouselPageIndex + 1) % totalPages
        updateTitle()
    }

    private func renderTickerImage(entries: [MenuBarTickerEntry], appearance: MenuBarTickerAppearance, barHeight: CGFloat) -> NSImage {
        if appearance.layoutMode == .vertical {
            return renderTickerImageVertical(entries: entries, appearance: appearance, barHeight: barHeight)
        }
        return renderTickerImageHorizontal(entries: entries, appearance: appearance, barHeight: barHeight)
    }

    private func renderTickerImageHorizontal(entries: [MenuBarTickerEntry], appearance: MenuBarTickerAppearance, barHeight: CGFloat) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(appearance.fontSize), weight: appearance.fontWeight)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let texts = entries.map(\.compactText)
        let measurements = texts.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
        let itemSpacing = appearance.spacingMode == .manual ? CGFloat(appearance.manualSpacing) : max(8, CGFloat(appearance.fontSize) * 1.05)
        let horizontalPadding: CGFloat = 3
        let measuredWidth = measurements.reduce(0, +) + CGFloat(max(0, texts.count - 1)) * itemSpacing + horizontalPadding * 2
        let width = ceil(appearance.widthMode == .manual ? CGFloat(appearance.manualWidth) : measuredWidth)

        let image = NSImage(size: NSSize(width: width, height: barHeight))
        image.lockFocusFlipped(true)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: appearance.nsColor ?? NSColor.black,
            .paragraphStyle: paragraph
        ]
        let top = max(0, floor((barHeight - lineHeight) / 2))
        var x = horizontalPadding
        for (index, text) in texts.enumerated() {
            let remainingWidth = width - x - horizontalPadding
            guard remainingWidth > 4 else { break }
            let drawWidth = min(measurements[index], remainingWidth)
            let rect = NSRect(x: x, y: top, width: drawWidth, height: lineHeight)
            NSAttributedString(string: text, attributes: attrs)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            x += drawWidth + itemSpacing
        }

        image.unlockFocus()
        image.isTemplate = appearance.nsColor == nil
        return image
    }

    private func renderTickerImageVertical(entries: [MenuBarTickerEntry], appearance: MenuBarTickerAppearance, barHeight: CGFloat) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(appearance.fontSize), weight: appearance.fontWeight)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let texts = entries.map(\.compactText)
        let measurements = texts.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
        let maxWidth = measurements.max() ?? 0
        let horizontalPadding: CGFloat = 3
        let measuredWidth = maxWidth + horizontalPadding * 2
        let width = ceil(appearance.widthMode == .manual ? CGFloat(appearance.manualWidth) : measuredWidth)
        let lineSpacing = appearance.spacingMode == .manual ? CGFloat(appearance.manualSpacing) : 0

        let image = NSImage(size: NSSize(width: width, height: barHeight))
        image.lockFocusFlipped(true)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: appearance.nsColor ?? NSColor.black,
            .paragraphStyle: paragraph
        ]
        let totalHeight = CGFloat(texts.count) * lineHeight + CGFloat(max(0, texts.count - 1)) * lineSpacing
        let top = max(0, floor((barHeight - totalHeight) / 2))
        let textWidth = width - horizontalPadding * 2
        for (i, text) in texts.enumerated() {
            let rect = NSRect(
                x: horizontalPadding,
                y: top + CGFloat(i) * (lineHeight + lineSpacing),
                width: textWidth,
                height: lineHeight
            )
            NSAttributedString(string: text, attributes: attrs)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        image.unlockFocus()
        image.isTemplate = appearance.nsColor == nil
        return image
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    @MainActor func createMainWindow() {
        guard let model else { return }
        let contentView = ContentView()
            .environmentObject(model)
            .tint(AppPalette.brand)
            .preferredColorScheme(model.appearance.colorScheme)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.title = "且慢主理人"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        // Transparent toolbar for proper content-under-titlebar layout
        // without occluding content behind the system title bar area.
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        window.appearance = model.appearance.nsAppearance
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.appearance = model.appearance.nsAppearance
        window.contentView = hostingView
        window.delegate = self
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Intercepts the window close action: hides the window instead of destroying it
    /// so the app stays alive (accessible via menu bar). The user can reopen the
    /// window from the status bar icon or the "打开主窗口" menu command.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    @MainActor func showMainWindow() {
        // 1. Re-show the tracked main window if it still exists.
        if let window = mainWindow {
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            return
        }
        // 2. Search for an existing SwiftUI WindowGroup window (may have been hidden
        //    by windowShouldClose but never tracked in mainWindow).
        if let existing = NSApplication.shared.windows.first(where: {
            $0.isVisible == false
                && $0.canBecomeMain
                && !($0 is NSPanel)
                && $0.title == "且慢主理人"
        }) {
            mainWindow = existing
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        // 3. No window at all — create one.
        createMainWindow()
    }

    /// Exposes the stored main window reference for zoom toggling.
    /// Returns `nil` if the window has been destroyed or is a panel/sheet.
    @MainActor var mainWindowForZoom: NSWindow? {
        guard let win = mainWindow, win.isVisible, win.canBecomeMain else { return nil }
        return win
    }

    // MARK: - Titlebar Double-Click Zoom

    /// Intercepts double-clicks in the native titlebar / unified toolbar region and
    /// forwards them as zoom toggles.  This is needed because the window uses
    /// `.hiddenTitleBar` + `titlebarAppearsTransparent = true`, which means SwiftUI
    /// tap gestures cannot reach the macOS-owned titlebar area above the content view.
    private func handleTitlebarDoubleClick(_ event: NSEvent) -> NSEvent {
        // Only care about double-clicks
        guard event.clickCount == 2 else { return event }

        let window = event.window

        // Only target our main window — skip panels, popovers, sheets
        guard let win = window,
              win == mainWindow,
              !(win is NSPanel),
              !win.isSheet,
              win.styleMask.contains(.resizable)
        else { return event }

        // Convert the click location to window coordinates
        let clickPoint = event.locationInWindow

        // Determine the titlebar height:
        // For a window with a toolbar (unified style), the titlebar region is the area
        // above the content view's frame. With fullSizeContentView, the content view
        // spans the full window, but the "titlebar" region is still the top portion
        // defined by the window's frameRect(forContentRect:) difference.
        let contentFrame = win.contentView?.frame ?? .zero
        let contentRectForContentRect = win.contentRect(forFrameRect: win.frame)
        let titlebarHeight = win.frame.height - contentRectForContentRect.height

        if MainWindowZoomPolicy.isInDoubleClickZoomBand(
            clickY: clickPoint.y,
            contentHeight: contentFrame.height,
            nativeTitlebarHeight: titlebarHeight
        ) {
            win.performZoom(nil)
            // Swallow the event so it doesn't propagate further
            return NSEvent()  // dummy event — effectively swallowed
        }

        return event
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let deepLink = NotificationDeepLinkPayload(userInfo: userInfo) else { return }
        NotificationCenter.default.post(name: .qiemanNotificationDeepLink, object: deepLink)
    }

    deinit {
        carouselTimer?.invalidate()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let titlebarDoubleClickMonitor {
            NSEvent.removeMonitor(titlebarDoubleClickMonitor)
        }
    }
}

// MARK: - NSWindowDelegate

extension QiemanApplicationDelegate: NSWindowDelegate {
    /// When the user clicks the red close button, hide the window instead of
    /// destroying it. This prevents the app from "exiting" — the user can
    /// reopen it via the menu bar icon or by clicking the Dock icon.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

@MainActor
private enum QiemanAppModelHolder {
    static let shared = AppModel()
}

@main
struct QiemanDashboardApp: App {
    @NSApplicationDelegateAdaptor(QiemanApplicationDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let sharedModel = QiemanAppModelHolder.shared
        _model = StateObject(wrappedValue: sharedModel)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .tint(AppPalette.brand)
                .preferredColorScheme(model.appearance.colorScheme)
                .onAppear {
                    appDelegate.configure(model: model)
                    // Sync initial appearance to NSWindow + NSHostingView level so
                    // NSColor dynamic colors (AppPalette.adaptive) resolve correctly
                    // from launch.
                    let target = model.appearance.nsAppearance
                    for window in NSApplication.shared.windows {
                        window.appearance = target
                        for view in window.contentView?.subviews ?? [] {
                            (view as? NSHostingView<AnyView>)?.appearance = target
                        }
                    }
                    // Track the SwiftUI WindowGroup window so that
                    // showMainWindow() can re-show it instead of creating a
                    // duplicate via createMainWindow().
                    if let keyWin = NSApp.keyWindow ?? NSApplication.shared.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
                        appDelegate.mainWindow = keyWin
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("打开主窗口") {
                    Task { @MainActor in
                        appDelegate.showMainWindow()
                    }
                }
                .keyboardShortcut("0")
                Button("打开数据目录") {
                    model.openDataDirectory()
                }
                Button("登录且慢") {
                    model.presentLoginSheet()
                }
                Divider()
                Button(model.isCheckingForUpdates ? "检查更新中…" : "检查更新…") {
                    Task { await model.checkForUpdates(userInitiated: true) }
                }
                .disabled(model.isCheckingForUpdates)
                Divider()
                Button("立即刷新") {
                    Task { try? await model.refreshLatest(persist: false) }
                }
                .keyboardShortcut("r")
            }
        }
    }
}
