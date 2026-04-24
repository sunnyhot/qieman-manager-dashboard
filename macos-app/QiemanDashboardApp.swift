import AppKit
import SwiftUI
import UserNotifications

private enum AppSceneIdentifier {
    static let mainWindow = "main-window"
}

final class QiemanApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
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
        }
        menuBarScene
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

    @SceneBuilder
    private var menuBarScene: some Scene {
        if #available(macOS 13.0, *) {
            MenuBarExtra {
                MenuBarPortfolioView()
                    .environmentObject(model)
            } label: {
                Label {
                    Text(model.portfolioMenuBarTitle)
                } icon: {
                    Image(systemName: "briefcase.fill")
                }
            }
            .menuBarExtraStyle(.window)
        }
    }
}
