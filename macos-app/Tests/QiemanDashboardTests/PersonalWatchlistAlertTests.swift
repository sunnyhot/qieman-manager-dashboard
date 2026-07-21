import Foundation
import XCTest
@testable import QiemanDashboard

final class PersonalWatchlistAlertTests: XCTestCase {
    func testPriceAboveTriggersOnceAndRearmsAfterReturningBelowThreshold() {
        let rules = PersonalWatchlistAlertRules(priceAbove: 100)

        let below = evaluate(rules: rules, price: 99)
        XCTAssertTrue(below.triggers.isEmpty)
        XCTAssertTrue(below.nextState.breachedKinds.isEmpty)

        let reached = evaluate(rules: rules, state: below.nextState, price: 100)
        XCTAssertEqual(reached.triggers.map(\.kind), [.priceAbove])
        XCTAssertTrue(reached.nextState.breachedKinds.contains(.priceAbove))

        let stillAbove = evaluate(rules: rules, state: reached.nextState, price: 105)
        XCTAssertTrue(stillAbove.triggers.isEmpty)
        XCTAssertTrue(stillAbove.nextState.breachedKinds.contains(.priceAbove))

        let rearmed = evaluate(rules: rules, state: stillAbove.nextState, price: 99)
        XCTAssertTrue(rearmed.triggers.isEmpty)
        XCTAssertFalse(rearmed.nextState.breachedKinds.contains(.priceAbove))

        let reachedAgain = evaluate(rules: rules, state: rearmed.nextState, price: 101)
        XCTAssertEqual(reachedAgain.triggers.map(\.kind), [.priceAbove])
    }

    func testPriceBelowAndGainLossRulesUseInclusiveBoundaries() {
        let rules = PersonalWatchlistAlertRules(
            priceBelow: 90,
            gainSinceFollowPct: 10,
            lossSinceFollowPct: 10
        )

        let gain = evaluate(rules: rules, price: 110, baseline: 100)
        XCTAssertEqual(gain.triggers.map(\.kind), [.gainSinceFollow])

        let loss = evaluate(rules: rules, price: 90, baseline: 100)
        XCTAssertEqual(Set(loss.triggers.map(\.kind)), Set([.priceBelow, .lossSinceFollow]))
    }

    func testMissingQuotePreservesBreachedStateInsteadOfRearming() {
        let rules = PersonalWatchlistAlertRules(priceAbove: 100)
        let state = PersonalWatchlistAlertState(
            breachedKinds: [.priceAbove],
            lastTriggeredAtByKind: [.priceAbove: "2026-07-21 10:00:00"]
        )

        let evaluation = evaluate(rules: rules, state: state, price: nil)

        XCTAssertTrue(evaluation.triggers.isEmpty)
        XCTAssertTrue(evaluation.nextState.breachedKinds.contains(.priceAbove))
        XCTAssertEqual(
            evaluation.nextState.lastTriggeredAtByKind[.priceAbove],
            "2026-07-21 10:00:00"
        )
    }

    func testMissingBaselineSkipsPercentRulesButStillEvaluatesPriceRules() {
        let rules = PersonalWatchlistAlertRules(priceAbove: 100, gainSinceFollowPct: 5)

        let evaluation = evaluate(rules: rules, price: 101, baseline: nil)

        XCTAssertEqual(evaluation.triggers.map(\.kind), [.priceAbove])
        XCTAssertFalse(evaluation.nextState.breachedKinds.contains(.gainSinceFollow))
    }

    func testUncommittedTriggerRemainsArmedWhenNotificationPermissionIsUnavailable() {
        let rules = PersonalWatchlistAlertRules(priceAbove: 100)

        let evaluation = PersonalWatchlistAlertEvaluator.evaluate(
            rules: rules,
            previousState: PersonalWatchlistAlertState(),
            currentPrice: 101,
            baselinePrice: 90,
            triggeredAt: "2026-07-21 10:00:00",
            commitNewTriggers: false
        )

        XCTAssertEqual(evaluation.triggers.map(\.kind), [.priceAbove])
        XCTAssertFalse(evaluation.nextState.breachedKinds.contains(.priceAbove))
    }

    func testRecordUpdatesAndStoreRoundTripPreserveAlertRulesAndState() throws {
        let rules = PersonalWatchlistAlertRules(priceAbove: 220, lossSinceFollowPct: 8)
        let state = PersonalWatchlistAlertState(
            breachedKinds: [.priceAbove],
            lastTriggeredAtByKind: [.priceAbove: "2026-07-21 10:00:00"]
        )
        let record = PersonalWatchlistRecord(
            item: item(),
            baseline: PersonalWatchlistBaseline(
                price: 210,
                quotedAt: "2026-07-20",
                capturedAt: "2026-07-20 10:00:00",
                sourceLabel: "股票行情"
            ),
            alertRules: rules,
            alertState: state
        )
        let updated = record.updating(
            displayName: "Apple",
            appending: [PersonalWatchlistDailyPoint(date: "2026-07-21", price: 221)]
        )

        XCTAssertEqual(updated.alertRules, rules)
        XCTAssertEqual(updated.alertState, state)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-watchlist-alert-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("user-watchlist.json")
        let store = PersonalWatchlistStore()

        try store.save([updated], to: fileURL)
        let loaded = try XCTUnwrap(store.load(from: fileURL).first)

        XCTAssertEqual(loaded.alertRules, rules)
        XCTAssertEqual(loaded.alertState, state)
    }

    func testRecordWithoutAlertKeysStillDecodes() throws {
        let record = PersonalWatchlistRecord(item: item())
        let encoded = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["alertRules"])
        XCTAssertNil(object["alertState"])

        let decoded = try JSONDecoder().decode(PersonalWatchlistRecord.self, from: encoded)
        XCTAssertNil(decoded.alertRules)
        XCTAssertNil(decoded.alertState)
    }

    private func evaluate(
        rules: PersonalWatchlistAlertRules,
        state: PersonalWatchlistAlertState = PersonalWatchlistAlertState(),
        price: Double?,
        baseline: Double? = 100
    ) -> PersonalWatchlistAlertEvaluation {
        PersonalWatchlistAlertEvaluator.evaluate(
            rules: rules,
            previousState: state,
            currentPrice: price,
            baselinePrice: baseline,
            triggeredAt: "2026-07-21 10:00:00"
        )
    }

    private func item() -> PersonalWatchlistItem {
        PersonalWatchlistItem(
            code: "AAPL",
            displayName: "苹果",
            assetType: .stock,
            stockMarket: .us,
            followedAt: "2026-07-20 10:00:00"
        )
    }
}
