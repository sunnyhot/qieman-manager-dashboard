import XCTest
@testable import QiemanDashboard

final class TrendAutoAnalysisScheduleTests: XCTestCase {
    func testDefaultScheduleUsesMorningAndAfternoonSlots() {
        let schedule = TrendAutoAnalysisSchedule.default

        XCTAssertEqual(schedule.timeStrings, ["09:30", "14:30"])
        XCTAssertNil(schedule.dueSlot(at: "2026-06-22 09:29:59", lastCompletedSlotKey: nil, legacyLastAutoAnalysisDay: nil))
        XCTAssertEqual(
            schedule.dueSlot(at: "2026-06-22 09:30:00", lastCompletedSlotKey: nil, legacyLastAutoAnalysisDay: nil)?.key,
            "2026-06-22 09:30"
        )
        XCTAssertEqual(
            schedule.dueSlot(at: "2026-06-22 15:00:00", lastCompletedSlotKey: nil, legacyLastAutoAnalysisDay: nil)?.key,
            "2026-06-22 14:30"
        )
    }

    func testScheduleSkipsCompletedSlotButAllowsLaterSlot() {
        let schedule = TrendAutoAnalysisSchedule(timeStrings: ["09:30", "14:30"])

        XCTAssertNil(
            schedule.dueSlot(
                at: "2026-06-22 10:00:00",
                lastCompletedSlotKey: "2026-06-22 09:30",
                legacyLastAutoAnalysisDay: nil
            )
        )
        XCTAssertEqual(
            schedule.dueSlot(
                at: "2026-06-22 15:00:00",
                lastCompletedSlotKey: "2026-06-22 09:30",
                legacyLastAutoAnalysisDay: nil
            )?.key,
            "2026-06-22 14:30"
        )
        XCTAssertNil(
            schedule.dueSlot(
                at: "2026-06-22 16:00:00",
                lastCompletedSlotKey: "2026-06-22 14:30",
                legacyLastAutoAnalysisDay: nil
            )
        )
    }

    func testScheduleNormalizesMultipleTimeTexts() {
        XCTAssertEqual(
            TrendAutoAnalysisSchedule(timeStrings: ["9:05", " 18:45 ", "bad", "09:05"]).timeStrings,
            ["09:05", "18:45"]
        )
        XCTAssertEqual(TrendAutoAnalysisSchedule(timeStrings: ["25:00", "bad"]).timeStrings, ["09:30", "14:30"])
        XCTAssertEqual(TrendAutoAnalysisSchedule(text: "14:30， 09:30 18:45").timeStrings, ["09:30", "14:30", "18:45"])
    }

    func testLegacyCompletedDaySuppressesRemainingSlotsForThatDay() {
        let schedule = TrendAutoAnalysisSchedule.default

        XCTAssertNil(
            schedule.dueSlot(
                at: "2026-06-22 15:00:00",
                lastCompletedSlotKey: nil,
                legacyLastAutoAnalysisDay: "2026-06-22"
            )
        )
        XCTAssertEqual(
            schedule.dueSlot(
                at: "2026-06-23 10:00:00",
                lastCompletedSlotKey: nil,
                legacyLastAutoAnalysisDay: "2026-06-22"
            )?.key,
            "2026-06-23 09:30"
        )
    }
}
