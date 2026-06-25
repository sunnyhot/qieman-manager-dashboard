import XCTest
@testable import QiemanDashboard

final class MenuBarTickerAppearanceTests: XCTestCase {
    func testDefaultLayoutUsesVerticalMenuBarDisplay() {
        XCTAssertEqual(MenuBarTickerAppearance.default.layoutMode, .vertical)
        XCTAssertEqual(MenuBarTickerSettings.default.appearance.layoutMode, .vertical)
    }

    func testLoadMigratesStoredHorizontalLayoutToVerticalOnce() throws {
        let defaults = UserDefaults.standard
        let previousData = defaults.data(forKey: MenuBarTickerSettings.storageKey)
        let previousMigration = defaults.object(forKey: MenuBarTickerSettings.verticalLayoutMigrationKey)
        defer {
            if let previousData {
                defaults.set(previousData, forKey: MenuBarTickerSettings.storageKey)
            } else {
                defaults.removeObject(forKey: MenuBarTickerSettings.storageKey)
            }
            if let previousMigration {
                defaults.set(previousMigration, forKey: MenuBarTickerSettings.verticalLayoutMigrationKey)
            } else {
                defaults.removeObject(forKey: MenuBarTickerSettings.verticalLayoutMigrationKey)
            }
        }

        let stored = MenuBarTickerSettings(
            isEnabled: true,
            maxVisibleItems: 2,
            selections: [.kind(.overallDailyPct)],
            appearance: MenuBarTickerAppearance(layoutMode: .horizontal)
        )
        defaults.set(try JSONEncoder().encode(stored), forKey: MenuBarTickerSettings.storageKey)
        defaults.removeObject(forKey: MenuBarTickerSettings.verticalLayoutMigrationKey)

        let loaded = MenuBarTickerSettings.load()

        XCTAssertEqual(loaded.appearance.layoutMode, .vertical)
        XCTAssertEqual(defaults.bool(forKey: MenuBarTickerSettings.verticalLayoutMigrationKey), true)
    }

    func testVerticalDefaultManualWidthNormalizesToAutomaticWidth() {
        let appearance = MenuBarTickerAppearance(
            layoutMode: .vertical,
            widthMode: .manual,
            manualWidth: MenuBarTickerAppearance.default.manualWidth
        )

        XCTAssertEqual(appearance.normalized().widthMode, .automatic)
    }

    func testVerticalCustomManualWidthRemainsManual() {
        let appearance = MenuBarTickerAppearance(
            layoutMode: .vertical,
            widthMode: .manual,
            manualWidth: 128
        )

        let normalized = appearance.normalized()

        XCTAssertEqual(normalized.widthMode, .manual)
        XCTAssertEqual(normalized.manualWidth, 128)
    }

    func testVerticalStatusWidthUsesCompactHorizontalPadding() {
        let appearance = MenuBarTickerAppearance(
            layoutMode: .vertical,
            widthMode: .automatic
        )

        XCTAssertEqual(MenuBarTickerLayoutMetrics.statusHorizontalPadding(for: appearance), 1)
        XCTAssertEqual(
            MenuBarTickerLayoutMetrics.statusImageWidth(measurements: [120, 72], appearance: appearance),
            122
        )
    }

    func testPreviewPaddingUsesCompactValues() {
        XCTAssertEqual(MenuBarTickerLayoutMetrics.previewHorizontalPadding, 6)
        XCTAssertEqual(MenuBarTickerLayoutMetrics.previewVerticalPadding, 5)
    }
}
