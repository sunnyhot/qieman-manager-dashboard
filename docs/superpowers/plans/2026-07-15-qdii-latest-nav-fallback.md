# QDII Latest NAV Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure off-exchange QDII holdings still receive their latest official NAV, market value, and cumulative profit when the primary intraday quote endpoint returns `jsonpgz();`.

**Architecture:** Keep `QiemanPlatformNativeClient` as the single producer of `NativeFundQuote`. Inject its `URLSession` for deterministic tests, add a lightweight Eastmoney latest-NAV request between the primary quote and full-history fallbacks, and prevent unusable histories or quotes from entering the normal caches. Exercise the complete public `fetchUserPortfolioSnapshot` path with a custom `URLProtocol` rather than testing private parsing helpers.

**Tech Stack:** Swift 5.9, Foundation `URLSession`/`URLProtocol`, XCTest, Swift Package Manager, macOS 14+

## Global Constraints

- Preserve the existing `UserPortfolioHolding`, `UserPortfolioValuationRow`, and persisted JSON wire formats.
- Preserve the existing primary quote behavior for funds that return usable `fundgz` data.
- Map fallback `DWJZ` and `FSRQ` to official NAV fields; do not map delayed QDII `JZZZL` to the UI's “今日涨跌”.
- Retain the full-history series as the final fallback and do not refactor platform trade-history behavior.
- Add no third-party dependencies; the Python server remains zero-dependency and unchanged.
- Do not log cookies or third-party response bodies.
- Leave the user's unrelated `.zcode/` working-tree content untouched.

## File Structure

- Modify `macos-app/Core/QiemanPlatformNativeClient.swift`: inject the network session, request and map lightweight latest NAV, and reject unusable cache entries.
- Create `macos-app/Tests/QiemanDashboardTests/QiemanPlatformFundQuoteFallbackTests.swift`: end-to-end mocked-network regression tests through `fetchUserPortfolioSnapshot`.
- No UI, Python, persisted-data, or release metadata files change.

---

### Task 1: Add the lightweight latest-NAV fallback

**Files:**
- Create: `macos-app/Tests/QiemanDashboardTests/QiemanPlatformFundQuoteFallbackTests.swift`
- Modify: `macos-app/Core/QiemanPlatformNativeClient.swift:160-169`
- Modify: `macos-app/Core/QiemanPlatformNativeClient.swift:924-985`
- Modify: `macos-app/Core/QiemanPlatformNativeClient.swift:1157-1210`

**Interfaces:**
- Consumes: `QiemanPlatformNativeClient.fetchUserPortfolioSnapshot(holdings:) async throws -> UserPortfolioSnapshot` and the existing `NativeFundQuote` mapping.
- Produces: `QiemanPlatformNativeClient.init(session: URLSession = .shared)` and private `fetchLatestFundNavQuote(_:fundName:) async throws -> NativeFundQuote?`.

- [ ] **Step 1: Write the failing mocked-network regression tests**

Create `macos-app/Tests/QiemanDashboardTests/QiemanPlatformFundQuoteFallbackTests.swift` with:

```swift
import Foundation
import XCTest
@testable import QiemanDashboard

final class QiemanPlatformFundQuoteFallbackTests: XCTestCase {
    override func tearDown() {
        MockQiemanPlatformURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testPortfolioUsesLatestOfficialNavWhenPrimaryQuoteIsEmpty() async throws {
        let expectedNAVs = [
            "002286": 1.2021,
            "100050": 1.2672,
            "006327": 0.8629,
        ]

        MockQiemanPlatformURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.host {
            case "fund.eastmoney.com":
                return Self.response(
                    for: url,
                    data: Data("""
                    var fS_name = "测试 QDII";
                    var Data_netWorthTrend = [];
                    """.utf8)
                )
            case "fundgz.1234567.com.cn":
                return Self.response(for: url, data: Data("jsonpgz();".utf8))
            case "api.fund.eastmoney.com":
                let code = try XCTUnwrap(Self.queryValue("fundCode", in: url))
                let nav = try XCTUnwrap(expectedNAVs[code])
                let data = try JSONSerialization.data(withJSONObject: [
                    "ErrCode": 0,
                    "Data": [
                        "LSJZList": [[
                            "DWJZ": String(format: "%.4f", nav),
                            "FSRQ": "2026-07-13",
                            "JZZZL": "-0.21",
                        ]],
                    ],
                ])
                return Self.response(for: url, data: data)
            default:
                XCTFail("Unexpected request: \(url.absoluteString)")
                throw URLError(.unsupportedURL)
            }
        }

        let client = makeClient()
        let holdings = expectedNAVs.keys.map {
            UserPortfolioHolding(
                fundCode: $0,
                assetType: .fund,
                units: 100,
                costPrice: 1,
                displayName: "测试基金 \($0)",
                fundMarket: .offExchange
            )
        }

        let snapshot = try await client.fetchUserPortfolioSnapshot(holdings: holdings)
        let rowsByCode = Dictionary(uniqueKeysWithValues: snapshot.rows.map {
            ($0.holding.normalizedFundCode, $0)
        })

        for (code, nav) in expectedNAVs {
            let row = try XCTUnwrap(rowsByCode[code])
            XCTAssertEqual(row.currentPrice, nav)
            XCTAssertEqual(row.officialNav, nav)
            XCTAssertEqual(row.officialNavDate, "2026-07-13")
            XCTAssertEqual(try XCTUnwrap(row.marketValue), nav * 100, accuracy: 0.001)
            XCTAssertNil(row.estimatePrice)
            XCTAssertNil(row.estimateChangePct)
        }
    }

    func testInvalidLatestNavResponseFallsBackToHistory() async throws {
        MockQiemanPlatformURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.host {
            case "fund.eastmoney.com":
                return Self.response(
                    for: url,
                    data: Data("""
                    var fS_name = "历史兜底基金";
                    var Data_netWorthTrend = [{"x":1783872000000,"y":1.1111}];
                    """.utf8)
                )
            case "fundgz.1234567.com.cn":
                return Self.response(for: url, data: Data("jsonpgz();".utf8))
            case "api.fund.eastmoney.com":
                let data = try JSONSerialization.data(withJSONObject: [
                    "ErrCode": 1,
                    "Data": ["LSJZList": []],
                ])
                return Self.response(for: url, data: data)
            default:
                XCTFail("Unexpected request: \(url.absoluteString)")
                throw URLError(.unsupportedURL)
            }
        }

        let snapshot = try await makeClient().fetchUserPortfolioSnapshot(
            holdings: [holding(code: "002286")]
        )
        let row = try XCTUnwrap(snapshot.rows.first)

        XCTAssertEqual(row.currentPrice, 1.1111)
        XCTAssertEqual(row.officialNav, 1.1111)
        XCTAssertEqual(row.priceSource, "最近净值")
        XCTAssertNil(row.estimateChangePct)
    }

    func testPrimaryQuoteRemainsHigherPriorityThanLatestNavFallback() async throws {
        MockQiemanPlatformURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.host {
            case "fund.eastmoney.com":
                return Self.response(
                    for: url,
                    data: Data("""
                    var fS_name = "正常估值基金";
                    var Data_netWorthTrend = [];
                    """.utf8)
                )
            case "fundgz.1234567.com.cn":
                return Self.response(
                    for: url,
                    data: Data("""
                    jsonpgz({"fundcode":"000369","name":"正常估值基金","jzrq":"2026-07-13","dwjz":"2.5060","gsz":"2.5074","gszzl":"0.06","gztime":"2026-07-15 04:00"});
                    """.utf8)
                )
            case "api.fund.eastmoney.com":
                XCTFail("Latest NAV endpoint must not run when the primary quote is usable")
                throw URLError(.unsupportedURL)
            default:
                XCTFail("Unexpected request: \(url.absoluteString)")
                throw URLError(.unsupportedURL)
            }
        }

        let snapshot = try await makeClient().fetchUserPortfolioSnapshot(
            holdings: [holding(code: "000369")]
        )
        let row = try XCTUnwrap(snapshot.rows.first)

        XCTAssertEqual(row.currentPrice, 2.5060)
        XCTAssertEqual(row.estimatePrice, 2.5074)
        XCTAssertEqual(row.estimateChangePct, 0.06)
    }

    private func makeClient() -> QiemanPlatformNativeClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockQiemanPlatformURLProtocol.self]
        return QiemanPlatformNativeClient(session: URLSession(configuration: configuration))
    }

    private func holding(code: String) -> UserPortfolioHolding {
        UserPortfolioHolding(
            fundCode: code,
            assetType: .fund,
            units: 100,
            costPrice: 1,
            displayName: "测试基金 \(code)",
            fundMarket: .offExchange
        )
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private static func response(for url: URL, data: Data) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

private final class MockQiemanPlatformURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd macos-app
swift test --filter QiemanPlatformFundQuoteFallbackTests
```

Expected: compilation fails because `QiemanPlatformNativeClient` does not yet accept `session:`. This is the intended RED failure proving the test requires an injectable client.

- [ ] **Step 3: Inject `URLSession` into the native client**

In `macos-app/Core/QiemanPlatformNativeClient.swift`, add the session property and initializer immediately after the cache configuration:

```swift
final class QiemanPlatformNativeClient {
    private let baseURL = URL(string: "https://qieman.com")!
    private let apiBase = "/pmdj/v2"
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private let anonymousID = "anon-\(QiemanPlatformNativeClient.sha256Hex(UUID().uuidString).prefix(16))"
    private let payloadTTL: TimeInterval = 120
    private let historyTTL: TimeInterval = 12 * 60 * 60
    private let quoteTTL: TimeInterval = 45
    private let cache = QiemanPlatformCache()
    private let session: URLSession
    private static let preloadConcurrencyLimit = 6

    init(session: URLSession = .shared) {
        self.session = session
    }
```

Replace both uses of the global shared session in `requestJSON` and `requestText`:

```swift
let (data, response) = try await session.data(for: request)
```

- [ ] **Step 4: Add the latest official NAV request and mapping**

In `fetchFundQuote`, insert this branch after primary `jsonpgz` parsing and before the existing history fallback:

```swift
if let latestQuote = try? await fetchLatestFundNavQuote(
    fundCode,
    fundName: history?.fundName ?? ""
) {
    return latestQuote
}
```

Add the following method immediately after `fetchFundQuote`:

```swift
private func fetchLatestFundNavQuote(_ fundCode: String, fundName: String) async throws -> NativeFundQuote? {
    var components = URLComponents(string: "https://api.fund.eastmoney.com/f10/lsjz")
    components?.queryItems = [
        URLQueryItem(name: "fundCode", value: fundCode),
        URLQueryItem(name: "pageIndex", value: "1"),
        URLQueryItem(name: "pageSize", value: "1"),
    ]
    guard let url = components?.url else {
        throw NativePlatformError.invalidResponse
    }

    let text = try await requestText(
        hostURL: URL(string: "https://api.fund.eastmoney.com")!,
        absoluteURL: url,
        headers: [
            "Accept": "application/json",
            "Referer": "https://fund.eastmoney.com/",
        ]
    )
    guard let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          intValue(object["ErrCode"]) == 0,
          let payload = object["Data"] as? [String: Any],
          let rows = payload["LSJZList"] as? [[String: Any]],
          let latest = rows.first,
          let officialNav = doubleValue(latest["DWJZ"]),
          officialNav > 0 else {
        return nil
    }

    let officialNavDate = normalizedString(latest["FSRQ"])
    return NativeFundQuote(
        fundCode: fundCode,
        fundName: fundName,
        price: officialNav,
        priceTime: officialNavDate,
        priceSource: "official_nav",
        priceSourceLabel: "最近净值",
        officialNav: officialNav,
        officialNavDate: officialNavDate,
        estimatePrice: nil,
        estimateTime: "",
        estimateChangePct: nil
    )
}
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
cd macos-app
swift test --filter QiemanPlatformFundQuoteFallbackTests
```

Expected: all three tests pass; the primary-quote test makes no request to `api.fund.eastmoney.com`.

- [ ] **Step 6: Commit the first independently working change**

```bash
git add macos-app/Core/QiemanPlatformNativeClient.swift \
  macos-app/Tests/QiemanDashboardTests/QiemanPlatformFundQuoteFallbackTests.swift
git commit -m "fix: 为 QDII 增加最新净值兜底"
```

---

### Task 2: Prevent unusable fund data from entering normal caches

**Files:**
- Modify: `macos-app/Tests/QiemanDashboardTests/QiemanPlatformFundQuoteFallbackTests.swift`
- Modify: `macos-app/Core/QiemanPlatformNativeClient.swift:43-63`

**Interfaces:**
- Consumes: Task 1's injectable `QiemanPlatformNativeClient` and mocked URL protocol.
- Produces: cache behavior where empty `NativeFundHistory` and `NativeFundQuote` values remove stale entries and are retried on the next refresh.

- [ ] **Step 1: Add a failing retry test and thread-safe request counter**

Add this test method to `QiemanPlatformFundQuoteFallbackTests`:

```swift
func testUnavailableFundDataIsRetriedInsteadOfCached() async throws {
    let counter = LockedRequestCounter()
    MockQiemanPlatformURLProtocol.requestHandler = { request in
        let url = try XCTUnwrap(request.url)
        let key = url.host ?? "unknown"
        counter.increment(key)

        switch url.host {
        case "fund.eastmoney.com":
            return Self.response(
                for: url,
                data: Data("""
                var fS_name = "暂无数据基金";
                var Data_netWorthTrend = [];
                """.utf8)
            )
        case "fundgz.1234567.com.cn":
            return Self.response(for: url, data: Data("jsonpgz();".utf8))
        case "api.fund.eastmoney.com":
            let data = try JSONSerialization.data(withJSONObject: [
                "ErrCode": 0,
                "Data": ["LSJZList": []],
            ])
            return Self.response(for: url, data: data)
        default:
            XCTFail("Unexpected request: \(url.absoluteString)")
            throw URLError(.unsupportedURL)
        }
    }

    let client = makeClient()
    let holdings = [holding(code: "002286")]
    let first = try await client.fetchUserPortfolioSnapshot(holdings: holdings)
    let second = try await client.fetchUserPortfolioSnapshot(holdings: holdings)

    XCTAssertNil(first.rows.first?.marketValue)
    XCTAssertNil(second.rows.first?.marketValue)
    XCTAssertEqual(counter.value(for: "fund.eastmoney.com"), 2)
    XCTAssertEqual(counter.value(for: "fundgz.1234567.com.cn"), 2)
    XCTAssertEqual(counter.value(for: "api.fund.eastmoney.com"), 2)
}
```

Add this helper after `MockQiemanPlatformURLProtocol`:

```swift
private final class LockedRequestCounter {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func increment(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }

    func value(for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key, default: 0]
    }
}
```

- [ ] **Step 2: Run the retry test and verify RED**

Run:

```bash
cd macos-app
swift test --filter QiemanPlatformFundQuoteFallbackTests/testUnavailableFundDataIsRetriedInsteadOfCached
```

Expected: assertions report request counts of `1` instead of `2`, proving the current 12-hour history cache and 45-second quote cache retain unusable values.

- [ ] **Step 3: Reject unusable history and quote cache writes**

Replace the two `QiemanPlatformCache.store` overloads with:

```swift
fileprivate func store(history: NativeFundHistory, for fundCode: String) {
    guard !history.series.isEmpty else {
        histories.removeValue(forKey: fundCode)
        return
    }
    store(history, for: fundCode, in: &histories, maxEntries: Self.maxFundCacheEntries)
}

fileprivate func store(quote: NativeFundQuote, for fundCode: String) {
    guard quote.price > 0 || (quote.officialNav ?? 0) > 0 || (quote.estimatePrice ?? 0) > 0 else {
        quotes.removeValue(forKey: fundCode)
        return
    }
    store(quote, for: fundCode, in: &quotes, maxEntries: Self.maxFundCacheEntries)
}
```

- [ ] **Step 4: Run the focused suite and verify GREEN**

Run:

```bash
cd macos-app
swift test --filter QiemanPlatformFundQuoteFallbackTests
```

Expected: all four fallback/cache tests pass with no warnings or unexpected requests.

- [ ] **Step 5: Commit the cache correction**

```bash
git add macos-app/Core/QiemanPlatformNativeClient.swift \
  macos-app/Tests/QiemanDashboardTests/QiemanPlatformFundQuoteFallbackTests.swift
git commit -m "fix: 不缓存不可用基金报价"
```

---

### Task 3: Close verification across the package and app build

**Files:**
- Verify only; no source files should change.

**Interfaces:**
- Consumes: Tasks 1-2 production code and regression tests.
- Produces: fresh unit, integration-style mocked-network, live-source, and app-build evidence.

- [ ] **Step 1: Run the complete Swift test suite**

```bash
cd macos-app
swift test
```

Expected: exit code `0`, including all `QiemanPlatformFundQuoteFallbackTests` cases.

- [ ] **Step 2: Smoke-check the live lightweight endpoint for the three affected codes**

From the repository root:

```bash
for code in 002286 100050 006327; do
  curl -fsSL -A 'Mozilla/5.0' \
    -e 'https://fund.eastmoney.com/' \
    "https://api.fund.eastmoney.com/f10/lsjz?fundCode=$code&pageIndex=1&pageSize=1" \
    | jq -e --arg code "$code" '.ErrCode == 0 and ((.Data.LSJZList[0].DWJZ | tonumber) > 0)'
done
```

Expected: three `true` values and exit code `0`. Treat a live-source failure as an external verification blocker, not a unit-test failure.

- [ ] **Step 3: Build the macOS app with the repository-native command**

From the repository root:

```bash
APP_VERSION=3.1.4 bash scripts/build_macos_app.sh
```

Expected: exit code `0` and `dist/macos-app/QiemanDashboard.app` produced. Do not replace or restart the running `/Applications/QiemanDashboard.app` without separate user authorization.

- [ ] **Step 4: Inspect the final diff and working tree**

```bash
git diff --check
git status --short
git log -3 --oneline
```

Expected: no whitespace errors; only the user's pre-existing `.zcode/` remains untracked; the two implementation commits are visible above the design/plan commits.
