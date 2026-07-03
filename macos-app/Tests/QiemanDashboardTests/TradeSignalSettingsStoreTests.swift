import XCTest
@testable import QiemanDashboard

final class TradeSignalSettingsStoreTests: XCTestCase {
    func testLoadReturnsDefaultWhenFileIsMissing() throws {
        let url = temporaryURL("missing-trade-signal-settings.json")

        let settings = try TradeSignalSettingsStore().load(from: url)

        XCTAssertTrue(settings.enabled)
        XCTAssertFalse(settings.localNotificationsEnabled)
        XCTAssertEqual(settings.riskPreference, .balanced)
        XCTAssertEqual(settings.primaryHorizon, .medium)
        XCTAssertEqual(settings.minimumConfidence, 60)
        XCTAssertTrue(settings.allowBuySignals)
        XCTAssertTrue(settings.allowSellSignals)
        XCTAssertTrue(settings.useStaleAnalysis)
        XCTAssertTrue(settings.assetPreferences.isEmpty)
    }

    func testSaveAndLoadKeepsGlobalAndAssetPreferences() throws {
        let url = temporaryURL("trade-signal-settings.json")
        let settings = TradeSignalSettings(
            enabled: true,
            localNotificationsEnabled: true,
            riskPreference: .conservative,
            primaryHorizon: .long,
            minimumConfidence: 75,
            allowBuySignals: true,
            allowSellSignals: false,
            useStaleAnalysis: true,
            assetPreferences: [
                TradeSignalAssetPreference(
                    assetKey: "fund-000001",
                    mode: .raiseAttention,
                    preferredHorizon: .short,
                    notes: "核心观察"
                )
            ]
        )

        try TradeSignalSettingsStore().save(settings, to: url)
        let loaded = try TradeSignalSettingsStore().load(from: url)

        XCTAssertEqual(loaded, settings)
    }

    func testLegacyPartialJSONMigratesMissingFieldsToDefaults() throws {
        let url = temporaryURL("legacy-trade-signal-settings.json")
        try """
        {
          "enabled" : false,
          "minimumConfidence" : 80
        }
        """.data(using: .utf8)!.write(to: url)

        let loaded = try TradeSignalSettingsStore().load(from: url)

        XCTAssertFalse(loaded.enabled)
        XCTAssertFalse(loaded.localNotificationsEnabled)
        XCTAssertEqual(loaded.riskPreference, .balanced)
        XCTAssertEqual(loaded.primaryHorizon, .medium)
        XCTAssertEqual(loaded.minimumConfidence, 80)
        XCTAssertTrue(loaded.allowBuySignals)
        XCTAssertTrue(loaded.allowSellSignals)
        XCTAssertTrue(loaded.useStaleAnalysis)
        XCTAssertTrue(loaded.assetPreferences.isEmpty)
    }

    private func temporaryURL(_ filename: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(filename, isDirectory: false)
    }
}
