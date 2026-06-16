import XCTest
@testable import QiemanDashboard

final class PerformanceTelemetryTests: XCTestCase {
    func testMeasureEmitsEventWithMetadata() {
        var events: [PerformanceTelemetryEvent] = []

        let value = PerformanceTelemetry.withSink({ events.append($0) }) {
            PerformanceTelemetry.measure("unit.sync", metadata: ["rowCount": "3"]) {
                "finished"
            }
        }

        XCTAssertEqual(value, "finished")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "unit.sync")
        XCTAssertEqual(events.first?.metadata["rowCount"], "3")
        XCTAssertGreaterThanOrEqual(events.first?.elapsedMilliseconds ?? -1, 0)
    }

    func testMeasureAsyncEmitsEvent() async {
        var events: [PerformanceTelemetryEvent] = []

        let value = await PerformanceTelemetry.withSink({ events.append($0) }) {
            await PerformanceTelemetry.measureAsync("unit.async", metadata: ["operation": "refresh"]) {
                "ok"
            }
        }

        XCTAssertEqual(value, "ok")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "unit.async")
        XCTAssertEqual(events.first?.metadata["operation"], "refresh")
    }

    func testMessageRedactsSensitiveMetadataAndSortsKeys() {
        let event = PerformanceTelemetryEvent(
            name: "unit.redaction",
            elapsedMilliseconds: 12.34,
            metadata: [
                "rowCount": "2",
                "cookie": "access_token=secret",
                "authorization": "Bearer secret",
                "note": String(repeating: "x", count: 90)
            ]
        )

        XCTAssertTrue(event.message.contains("unit.redaction 12.3ms"))
        XCTAssertTrue(event.message.contains("authorization=<redacted>"))
        XCTAssertTrue(event.message.contains("cookie=<redacted>"))
        XCTAssertTrue(event.message.contains("rowCount=2"))
        XCTAssertFalse(event.message.contains("access_token=secret"))
        XCTAssertFalse(event.message.contains("Bearer secret"))
        XCTAssertLessThan(event.message.count, 190)
    }
}
