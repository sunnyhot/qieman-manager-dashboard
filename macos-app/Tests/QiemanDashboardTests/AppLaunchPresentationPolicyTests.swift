import AppKit
import XCTest
@testable import QiemanDashboard

final class AppLaunchPresentationPolicyTests: XCTestCase {
    func testInitialLaunchStaysRegularEvenWhenDockPreferenceIsHidden() {
        XCTAssertEqual(
            AppLaunchPresentationPolicy.initialActivationPolicy(storedShowsInDock: false),
            .regular
        )
    }

    func testConfiguredPolicyUsesDockPreferenceAfterWindowExists() {
        XCTAssertEqual(AppLaunchPresentationPolicy.configuredActivationPolicy(showsInDock: true), .regular)
        XCTAssertEqual(AppLaunchPresentationPolicy.configuredActivationPolicy(showsInDock: false), .accessory)
    }

    func testNotificationDelegateIsOptInAtLaunch() {
        XCTAssertTrue(AppRuntimeCapabilities.shouldInstallNotificationDelegateAtLaunch(environment: [
            "QIEMAN_INSTALL_NOTIFICATION_DELEGATE_AT_LAUNCH": "1"
        ]))
        XCTAssertFalse(AppRuntimeCapabilities.shouldInstallNotificationDelegateAtLaunch(environment: [:]))
        XCTAssertFalse(AppRuntimeCapabilities.shouldInstallNotificationDelegateAtLaunch(environment: [
            "QIEMAN_INSTALL_NOTIFICATION_DELEGATE_AT_LAUNCH": "0"
        ]))
    }

    func testSwiftUISceneWindowDeduplicatesDifferentTrackedWindowRegardlessOfVisibility() {
        XCTAssertTrue(AppMainWindowTrackingPolicy.shouldDiscardPreviousTrackedWindow(
            hasPreviousTrackedWindow: true,
            isSameWindow: false,
            previousWindowIsVisible: true
        ))
        XCTAssertTrue(AppMainWindowTrackingPolicy.shouldDiscardPreviousTrackedWindow(
            hasPreviousTrackedWindow: true,
            isSameWindow: false,
            previousWindowIsVisible: false
        ))
        XCTAssertFalse(AppMainWindowTrackingPolicy.shouldDiscardPreviousTrackedWindow(
            hasPreviousTrackedWindow: true,
            isSameWindow: true,
            previousWindowIsVisible: true
        ))
        XCTAssertFalse(AppMainWindowTrackingPolicy.shouldDiscardPreviousTrackedWindow(
            hasPreviousTrackedWindow: false,
            isSameWindow: false,
            previousWindowIsVisible: false
        ))
    }

    @MainActor
    func testTrackingNewSceneDiscardsPreviousTrackedWindowEvenIfPreviousIsNotYetVisible() {
        let delegate = QiemanApplicationDelegate()
        let firstWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let secondWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        firstWindow.isReleasedWhenClosed = false
        secondWindow.isReleasedWhenClosed = false
        defer {
            firstWindow.delegate = nil
            secondWindow.delegate = nil
            firstWindow.orderOut(nil)
            firstWindow.close()
            secondWindow.orderOut(nil)
            secondWindow.close()
        }

        firstWindow.orderFront(nil)
        delegate.trackSwiftUISceneMainWindow(firstWindow)
        firstWindow.delegate = delegate
        firstWindow.orderOut(nil)
        secondWindow.orderFront(nil)
        delegate.trackSwiftUISceneMainWindow(secondWindow)

        XCTAssertTrue(delegate.mainWindow === secondWindow)
        XCTAssertNil(firstWindow.delegate)
        XCTAssertFalse(firstWindow.isVisible)
    }

    @MainActor
    func testShowMainWindowReusesVisibleUntrackedSwiftUIWindowBeforeCreatingFallback() {
        let delegate = QiemanApplicationDelegate()
        let existingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        existingWindow.isReleasedWhenClosed = false
        existingWindow.title = "QiemanDashboard"
        existingWindow.orderFront(nil)
        defer {
            existingWindow.orderOut(nil)
            existingWindow.close()
        }

        delegate.showMainWindow()

        XCTAssertTrue(delegate.mainWindow === existingWindow)
    }

    func testDidFinishLaunchingWaitsForSwiftUIWindowBeforeFallbackCreation() {
        XCTAssertFalse(AppLaunchWindowPolicy.shouldCreateImmediateManualWindowOnLaunch)
    }

    func testAppUsesOneIdentifiedSwiftUIWindowWithoutADelayedManualFallback() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("QiemanDashboardApp.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Window(\"且慢主理人\", id: AppSceneIdentifier.mainWindow)"))
        XCTAssertTrue(source.contains(".defaultSize(width: 1200, height: 800)"))
        XCTAssertTrue(source.contains("registerMainWindowSceneOpener"))
        XCTAssertFalse(source.contains("WindowGroup {"))
        XCTAssertFalse(source.contains("Task.sleep(nanoseconds: 500_000_000)"))
    }

    @MainActor
    func testDarkAppearanceOverridesALightSystemWindow() throws {
        let model = AppModel()
        let originalAppearance = model.appearance
        defer { model.appearance = originalAppearance }
        model.appearance = .dark

        let delegate = QiemanApplicationDelegate()
        delegate.configure(model: model)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        defer { window.close() }

        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .aqua)

        delegate.syncWindowAppearances(in: [window])

        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .darkAqua)
    }
}
