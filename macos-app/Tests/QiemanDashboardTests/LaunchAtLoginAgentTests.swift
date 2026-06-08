import XCTest
@testable import QiemanDashboard

final class LaunchAtLoginAgentTests: XCTestCase {
    func testPlistUsesOpenCommandForCurrentAppBundle() throws {
        let appURL = URL(fileURLWithPath: "/Applications/QiemanDashboard.app", isDirectory: true)
        let agent = LaunchAtLoginAgent(appBundleURL: appURL)

        let data = try agent.plistData()
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["Label"] as? String, LaunchAtLoginAgent.label)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(plist["LimitLoadToSessionType"] as? String, "Aqua")
        XCTAssertEqual(
            plist["ProgramArguments"] as? [String],
            ["/usr/bin/open", "/Applications/QiemanDashboard.app"]
        )
    }

    func testInstallAndUninstallManageAgentFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = URL(fileURLWithPath: "/Applications/QiemanDashboard.app", isDirectory: true)
        let agent = LaunchAtLoginAgent(agentDirectoryURL: directory, appBundleURL: appURL)

        try agent.install()

        XCTAssertTrue(agent.isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.plistURL.path))

        try agent.uninstall()

        XCTAssertFalse(agent.isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: agent.plistURL.path))
    }
}
