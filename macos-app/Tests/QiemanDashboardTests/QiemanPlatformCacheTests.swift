import XCTest
@testable import QiemanDashboard

final class QiemanPlatformCacheTests: XCTestCase {
    func testPayloadCacheIsBounded() async {
        let cache = QiemanPlatformCache()

        for index in 0..<(QiemanPlatformCache.maxPayloadEntries + 2) {
            await cache.store(payload: payload(prodCode: "P\(index)"), for: "P\(index)")
        }

        let first = await cache.payload(for: "P0", ttl: .greatestFiniteMagnitude)
        let last = await cache.payload(
            for: "P\(QiemanPlatformCache.maxPayloadEntries + 1)",
            ttl: .greatestFiniteMagnitude
        )
        XCTAssertNil(first)
        XCTAssertNotNil(last)
    }

    private func payload(prodCode: String) -> PlatformPayload {
        PlatformPayload(
            supported: true,
            prodCode: prodCode,
            count: 0,
            buyCount: 0,
            sellCount: 0,
            adjustmentCount: 0,
            latest: nil,
            actions: [],
            holdings: nil,
            timeline: [],
            error: nil
        )
    }
}
