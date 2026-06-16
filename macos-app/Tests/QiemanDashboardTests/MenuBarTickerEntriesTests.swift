import XCTest
@testable import QiemanDashboard

@MainActor
final class MenuBarTickerEntriesTests: XCTestCase {
    func testVisibleEntriesStopsBuildingAfterMaxVisibleItems() {
        let model = AppModel()
        model.menuBarTickerSettings = MenuBarTickerSettings(
            isEnabled: true,
            maxVisibleItems: 2,
            selections: [
                .kind(.sseIndexLevel),
                .kind(.csi300IndexLevel),
                .kind(.chinextIndexLevel)
            ]
        )
        model.marketIndexQuotes = [
            .sseComposite: quote(kind: .sseComposite, price: 3_000),
            .csi300: quote(kind: .csi300, price: 4_000),
            .chinext: quote(kind: .chinext, price: 2_000)
        ]
        var events: [PerformanceTelemetryEvent] = []

        let entries = PerformanceTelemetry.withSink({ events.append($0) }) {
            model.menuBarTickerVisibleEntries
        }

        XCTAssertEqual(entries.map(\.id), ["sseIndexLevel", "csi300IndexLevel"])
        let buildEvent = events.last { $0.name == "menuBar.entries.build" }
        XCTAssertEqual(buildEvent?.metadata["selectionCount"], "3")
        XCTAssertEqual(buildEvent?.metadata["entryCount"], "2")
    }

    private func quote(kind: MarketIndexKind, price: Double) -> MarketIndexQuote {
        MarketIndexQuote(
            kind: kind,
            name: kind.label,
            price: price,
            previousClose: price,
            changeAmount: 0,
            changePct: 0,
            quotedAt: "2026-06-16 15:00",
            sourceLabel: "测试"
        )
    }
}
