import XCTest
@testable import QiemanDashboard

final class UIExperienceRegressionTests: XCTestCase {
    func testPresentedAssetSheetDisablesBackgroundInteractionAndHover() throws {
        let browser = try source(at: "Views/PersonalAssetBrowser.swift")
        let row = try source(at: "Views/PersonalAsset/PersonalAssetTableRow.swift")
        let components = try source(at: "Views/SharedComponents.swift")

        XCTAssertTrue(browser.contains("let allowsInteraction = selectedDetailRow == nil"))
        XCTAssertTrue(browser.contains(".allowsHitTesting(allowsInteraction)"))
        XCTAssertTrue(browser.contains("allowsHoverFeedback: allowsInteraction"))
        XCTAssertTrue(row.contains("allowsHoverFeedback: allowsHoverFeedback"))
        XCTAssertTrue(components.contains(".onChange(of: allowsHoverFeedback)"))
        XCTAssertTrue(components.contains("isHovering = false"))
    }

    func testSharedInteractionPrimitivesSupportStaticSurfacesDismissibleToastsAndReducedMotion() throws {
        let source = try source(at: "Views/SharedComponents.swift")

        XCTAssertTrue(source.contains("func staticSurface("))
        XCTAssertTrue(source.contains("accessibilityReduceMotion"))
        XCTAssertTrue(source.contains("let onDismiss: (() -> Void)?"))
    }

    func testPersonalAssetPrimaryContentOpensDetailWithoutRequiringIconButton() throws {
        let source = try source(at: "Views/PersonalAsset/PersonalAssetTableRow.swift")

        XCTAssertTrue(source.contains("Button {\n                onOpenDetail?()"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"查看 \\(row.fundName) 详情\")"))

        let fullRowButton = try XCTUnwrap(source.range(of: ".overlay(alignment: .leading)"))
        let hoverSurface = try XCTUnwrap(source.range(of: ".interactiveSurface("))
        XCTAssertLessThan(
            source.distance(from: source.startIndex, to: fullRowButton.lowerBound),
            source.distance(from: source.startIndex, to: hoverSurface.lowerBound),
            "hover surface must wrap the transparent full-row button so it receives pointer events"
        )
        XCTAssertTrue(source.contains("lift: AppPalette.hoverLift"))
        XCTAssertTrue(source.contains(".contentShape(RoundedRectangle(cornerRadius: AppPalette.cardRadius))"))
    }

    func testSettingsControlsHaveSemanticsKeyboardSortingAndSafeResetConfirmation() throws {
        let components = try source(at: "Views/SettingsComponents.swift")
        let menuBar = try source(at: "Views/SettingsMenuBarPanel.swift")

        XCTAssertTrue(components.contains("Toggle(title, isOn: isOn)"))
        XCTAssertTrue(menuBar.contains("isConfirmingMenuBarReset"))
        XCTAssertTrue(menuBar.contains("向前移动"))
        XCTAssertTrue(menuBar.contains("向后移动"))
        XCTAssertFalse(menuBar.contains(".frame(width: 18, height: 18)"))
    }

    func testEditorsKeepValidationFeedbackInsideThePresentedSheet() throws {
        let sources = try [
            source(at: "Views/PersonalAsset/PersonalPendingTradeEditSheet.swift"),
            source(at: "Views/PersonalAsset/PersonalInvestmentPlanEditor.swift"),
            source(at: "Views/PersonalAssetCards.swift"),
        ]

        for source in sources {
            XCTAssertTrue(source.contains("inlineErrorMessage"))
        }
    }

    func testHiddenHorizontalOverflowIsNotUsedForPrimaryInformation() throws {
        let content = try source(at: "Views/ContentView.swift")
        let forum = try source(at: "Views/ForumSectionView.swift")

        XCTAssertFalse(content.contains("ScrollView(.horizontal, showsIndicators: false)"))
        XCTAssertFalse(forum.contains("ScrollView(.horizontal, showsIndicators: false)"))
    }

    func testMainNavigationHasKeyboardShortcuts() throws {
        let source = try source(at: "QiemanDashboardApp.swift")

        XCTAssertTrue(source.contains("CommandMenu(\"导航\")"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"1\")"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"6\")"))
        XCTAssertTrue(source.contains("NotificationCenter.default.post(name: .qiemanFocusSearch"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"f\")"))
    }

    func testDestructiveSettingsAndLoginActionsRequireConfirmation() throws {
        let account = try source(at: "Views/SettingsAccountPanel.swift")
        let login = try source(at: "Views/QiemanLoginView.swift")

        XCTAssertTrue(account.contains("恢复默认数据目录？"))
        XCTAssertTrue(login.contains("清除登录态？"))
        XCTAssertTrue(login.contains("isConfirmingClearLogin = true"))
    }

    private func source(at relativePath: String) throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
