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
            hasVisibleMainWindow: false
        ))
        XCTAssertFalse(AppLaunchWindowPolicy.shouldShowFallbackMainWindow(
            hasTrackedVisibleMainWindow: true,
            hasVisibleMainWindow: false
        ))
        XCTAssertFalse(AppLaunchWindowPolicy.shouldShowFallbackMainWindow(
            hasTrackedVisibleMainWindow: false,
            hasVisibleMainWindow: true
        ))
    }
}
