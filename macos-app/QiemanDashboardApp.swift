import AppKit
import Combine
import SwiftUI
import UserNotifications

private enum AppSceneIdentifier {
    static let mainWindow = "main-window"
}

final class QiemanApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: AppModel?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var didConfigure = false
    private var carouselPageIndex = 0
    private var carouselTimer: Timer?
    private var lastEntryIDs: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

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
    }

    func configure(model: AppModel) {
        guard !didConfigure else { return }
        didConfigure = true
        self.model = model
        Task { @MainActor in
            model.appDelegate = self
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            NSApplication.shared.setActivationPolicy(model.showsInDock ? .regular : .accessory)
            let view = MenuBarPortfolioView()
                .environmentObject(model)
            self.popover.contentViewController = NSHostingController(rootView: view)
            self.updateTitle()

            model.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.updateTitle()
                    }
                }
                .store(in: &self.cancellables)
        }
    }

    @MainActor private func updateTitle() {
        guard let model, let button = statusItem.button else { return }
        let allEntries = model.menuBarTickerAllCandidates
        let settings = model.menuBarTickerSettings.normalized()
        let appearance = settings.appearance.normalized()
        let pageSize = settings.maxVisibleItems

        // Reset page if entries changed
        let currentIDs = allEntries.map(\.id)
        if currentIDs != lastEntryIDs {
            lastEntryIDs = currentIDs
            carouselPageIndex = 0
        }

        let barHeight = NSStatusBar.system.thickness

        if allEntries.isEmpty {
            stopCarousel()
            let icon = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "QiemanDashboard") ?? NSImage()
            icon.isTemplate = true
            button.image = icon
            button.toolTip = model.portfolioMenuBarTitle
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

        let lines = displayEntries.map { $0.compactText }
        let image = renderTickerImage(entries: displayEntries, appearance: appearance, barHeight: barHeight)
        button.image = image
        let pageIndicator = totalPages > 1 ? " [\((safePage + 1))/\(totalPages)]" : ""
        button.toolTip = lines.joined(separator: "  ") + pageIndicator
        button.needsDisplay = true
        statusItem.length = image.size.width

        // Start carousel if needed
        if totalPages > 1 {
            startCarousel(interval: settings.carouselIntervalSeconds)
        }
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

    private func renderTextImage(lines: [String], fontSize: CGFloat, barHeight: CGFloat) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let totalHeight = CGFloat(lines.count) * lineHeight

        var maxWidth: CGFloat = 0
        for line in lines {
            let size = (line as NSString).size(withAttributes: [.font: font])
            maxWidth = max(maxWidth, ceil(size.width))
        }

        let horizontalPadding: CGFloat = 9
        let measurementSlack: CGFloat = 6
        let width = ceil(maxWidth + horizontalPadding * 2 + measurementSlack)

        let image = NSImage(size: NSSize(width: width, height: barHeight))
        image.lockFocusFlipped(true)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let top = max(0, floor((barHeight - totalHeight) / 2))
        let textWidth = width - horizontalPadding * 2
        for (i, line) in lines.enumerated() {
            let rect = NSRect(
                x: horizontalPadding,
                y: top + CGFloat(i) * lineHeight,
                width: textWidth,
                height: lineHeight
            )
            (line as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attrs)
        }

        image.unlockFocus()
        image.isTemplate = true
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
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
    }
}

@main
struct QiemanDashboardApp: App {
    @NSApplicationDelegateAdaptor(QiemanApplicationDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: AppSceneIdentifier.mainWindow) {
            ContentView()
                .environmentObject(model)
                .tint(AppPalette.brand)
                .preferredColorScheme(model.appearance.colorScheme)
                .onAppear {
                    appDelegate.configure(model: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
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
