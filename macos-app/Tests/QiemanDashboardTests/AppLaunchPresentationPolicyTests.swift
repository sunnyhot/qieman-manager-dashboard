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

    func testLaunchFallbackShowsMainWindowWhenNoWindowWasRestored() {
        XCTAssertTrue(AppLaunchWindowPolicy.shouldShowFallbackMainWindow(
            hasTrackedVisibleMainWindow: false,
            hasReusableMainWindow: false
        ))
        XCTAssertFalse(AppLaunchWindowPolicy.shouldShowFallbackMainWindow(
            hasTrackedVisibleMainWindow: true,
            hasReusableMainWindow: false
        ))
        XCTAssertFalse(AppLaunchWindowPolicy.shouldShowFallbackMainWindow(
            hasTrackedVisibleMainWindow: false,
            hasReusableMainWindow: true
        ))
    }

    func testLaunchFallbackSkipsManualWindowWhenReusableMainWindowExists() {
        XCTAssertFalse(AppLaunchWindowPolicy.shouldShowFallbackMainWindow(
            hasTrackedVisibleMainWindow: false,
            hasReusableMainWindow: true
        ))
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
}
