import XCTest
@testable import QiemanDashboard

final class AppUpdateReleaseNotesFormatterTests: XCTestCase {
    func testItemsHideMarkdownChromeAndAutomationFooter() {
        let rawNotes = """
        ## 且慢主理人看板 v2.7.3

        - fix: include release notes in update manifest

        ---
        🤖 自动构建 by GitHub Actions
        """

        XCTAssertEqual(
            AppUpdateReleaseNotesFormatter.items(from: rawNotes),
            ["升级弹窗现在只展示本次更新内容。"]
        )
    }

    func testItemsRemoveConventionalCommitPrefix() {
        XCTAssertEqual(
            AppUpdateReleaseNotesFormatter.items(from: "- feat: 优化更新弹窗样式"),
            ["优化更新弹窗样式"]
        )
    }
}
