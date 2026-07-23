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

    @MainActor
    func testAppearanceSelectionBroadcastsNativeWindowRefreshAndUsesAGeneralSettingsLabel() throws {
        let model = AppModel()
        let originalAppearance = model.appearance
        defer { model.appearance = originalAppearance }
        model.appearance = .system

        let notification = expectation(forNotification: .qiemanAppearanceDidChange, object: nil)
        model.appearance = .dark
        wait(for: [notification], timeout: 1)

        XCTAssertEqual(model.appearance, .dark)

        let settings = try source(at: "Views/SettingsSectionView.swift")
        XCTAssertTrue(settings.contains("title: \"通用\""))
        XCTAssertTrue(settings.contains("detail: \"当前外观 · \\(model.appearance.rawValue)\""))
        XCTAssertFalse(settings.contains("title: \"版本\""))
        XCTAssertFalse(settings.contains("?? \"当前构建\""))
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

    func testWorkspaceListsUseBoundedScrollViewportsWithoutDrawingPastTheirCards() throws {
        let fixedViewportSources = try [
            source(at: "Views/PlatformSectionView.swift"),
            source(at: "Views/Platform/AlfaPlatformPanel.swift"),
        ]

        for source in fixedViewportSources {
            XCTAssertFalse(source.contains(".fixedSize(horizontal: false, vertical: true)"))
            XCTAssertTrue(source.contains(".frame(height: PlatformWorkspaceLayout.actionListHeight)"))
            XCTAssertTrue(source.contains(".clipped()"))
        }

        let forum = try source(at: "Views/ForumSectionView.swift")
        XCTAssertFalse(forum.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(forum.contains("availableHeight: proxy.size.height"))
        XCTAssertTrue(forum.contains(".frame(height: PlatformWorkspaceLayout.forumListHeight(for: availableHeight))"))
        XCTAssertTrue(forum.contains(".clipped()"))
    }

    func testAlfaPanelUsesThePlatformWorkspaceScrollAndWidthContext() throws {
        let platform = try source(at: "Views/PlatformSectionView.swift")
        let alfa = try source(at: "Views/Platform/AlfaPlatformPanel.swift")

        XCTAssertTrue(platform.contains("AlfaPlatformPanel("))
        XCTAssertTrue(platform.contains("isCompact: isCompact"))
        XCTAssertTrue(platform.contains("availableWidth: proxy.size.width"))
        XCTAssertTrue(platform.contains("scrollProxy: scrollProxy"))
        XCTAssertFalse(alfa.contains("GeometryReader { proxy in"))
        XCTAssertFalse(alfa.contains("ScrollViewReader { scrollProxy in"))
        XCTAssertFalse(alfa.contains("ScrollView(showsIndicators: false)"))
    }

    func testMainNavigationHasKeyboardShortcuts() throws {
        let source = try source(at: "QiemanDashboardApp.swift")

        XCTAssertTrue(source.contains("CommandMenu(\"导航\")"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"1\")"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"6\")"))
        XCTAssertTrue(source.contains("NotificationCenter.default.post(name: .qiemanFocusSearch"))
        XCTAssertTrue(source.contains(".keyboardShortcut(\"f\")"))
    }

    func testQuitApplicationIsReachableFromMenuBarPopoverAndSettings() throws {
        let appModel = try source(at: "Core/AppModel/Auth.swift")
        let menuBar = try source(at: "Views/MenuBarPortfolioView.swift")
        let settings = try source(at: "Views/SettingsAppPanel.swift")

        XCTAssertTrue(appModel.contains("func quitApplication()"))
        XCTAssertTrue(appModel.contains("NSApplication.shared.terminate(nil)"))

        XCTAssertTrue(menuBar.contains("Button(\"退出应用\")"))
        XCTAssertTrue(menuBar.contains("model.quitApplication()"))

        XCTAssertTrue(settings.contains("Label(\"退出应用\", systemImage: \"power\")"))
        XCTAssertTrue(settings.contains("model.quitApplication()"))
    }

    func testMenuBarPopoverShowsAndRefreshesPersonalWatchlist() throws {
        let menuBar = try source(at: "Views/MenuBarPortfolioView.swift")

        XCTAssertTrue(menuBar.contains("Text(\"我的关注\")"))
        XCTAssertTrue(menuBar.contains("MenuBarWatchlistRow(row: row)"))
        XCTAssertTrue(menuBar.contains("percentOptional(row.changeSinceFollowPct)"))
        XCTAssertTrue(menuBar.contains("try? await model.refreshPersonalWatchlist(updateNotice: false)"))
        XCTAssertTrue(menuBar.contains("@AppStorage(\"menu.bar.popover.top-section\")"))
        XCTAssertTrue(menuBar.contains("Text(\"\\(section.title)在上\")"))
        XCTAssertTrue(menuBar.contains("ForEach(orderedSections)"))
    }

    func testMenuBarPopoverChecksForUpdatesInsteadOfOpeningTheDataDirectory() throws {
        let menuBar = try source(at: "Views/MenuBarPortfolioView.swift")
        let updateButtonStart = try XCTUnwrap(
            menuBar.range(of: "Button(model.isCheckingForUpdates ? \"检测中…\" : \"检测更新\")")
        )
        let quitButtonStart = try XCTUnwrap(
            menuBar.range(of: "Button(\"退出应用\")", range: updateButtonStart.upperBound..<menuBar.endIndex)
        )
        let updateButton = String(menuBar[updateButtonStart.lowerBound..<quitButtonStart.lowerBound])

        XCTAssertTrue(updateButton.contains("model.showMainWindow(section: .settings)"))
        XCTAssertTrue(updateButton.contains("await model.checkForUpdates(userInitiated: true)"))
        XCTAssertTrue(updateButton.contains(".disabled(model.isCheckingForUpdates)"))
        XCTAssertFalse(menuBar.contains("Button(\"数据目录\")"))
        XCTAssertFalse(menuBar.contains("model.openDataDirectory()"))
    }

    func testWatchlistLookupKeepsLocalResolutionWhileRefreshingTheName() throws {
        let watchlist = try source(at: "Views/PersonalWatchlistView.swift")

        XCTAssertTrue(watchlist.contains("model.preparePersonalWatchlistCode("))
        XCTAssertTrue(watchlist.contains(".onChange(of: lookupKey, initial: true)"))
        XCTAssertTrue(watchlist.contains("requestID == lookupRequestID"))
        XCTAssertTrue(watchlist.contains("resolution = resolved ?? prepared"))
        XCTAssertTrue(watchlist.contains(".disabled(resolution == nil || isSaving)"))
        XCTAssertFalse(watchlist.contains(".disabled(resolution == nil || isResolving || isSaving)"))
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
