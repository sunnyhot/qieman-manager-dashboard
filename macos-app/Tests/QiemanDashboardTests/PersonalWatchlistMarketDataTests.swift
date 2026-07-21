import Foundation
import XCTest
@testable import QiemanDashboard

final class PersonalWatchlistMarketDataTests: XCTestCase {
    override func tearDown() {
        PersonalWatchlistMockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testWatchlistCombinesFundHistoryAndExchangeTradedDailySeries() async throws {
        PersonalWatchlistMockURLProtocol.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            switch url.host {
            case "fund.eastmoney.com":
                return Self.response(
                    for: url,
                    data: Data("""
                    var fS_name = "测试场外基金";
                    var Data_netWorthTrend = [
                      {"x":1784476800000,"y":1.0100,"equityReturn":1.00},
                      {"x":1784563200000,"y":1.0200,"equityReturn":0.99}
                    ];
                    """.utf8)
                )
            case "api.fund.eastmoney.com":
                let data = try JSONSerialization.data(withJSONObject: [
                    "ErrCode": 0,
                    "Data": [
                        "LSJZList": [[
                            "DWJZ": "1.0200",
                            "FSRQ": "2026-07-21",
                            "JZZZL": "0.99",
                        ]],
                    ],
                ])
                return Self.response(for: url, data: data)
            case "push2.eastmoney.com":
                let data = try JSONSerialization.data(withJSONObject: [
                    "data": [
                        "f43": 4787,
                        "f57": "510300",
                        "f58": "沪深300ETF",
                        "f59": 3,
                        "f60": 4650,
                        "f170": 295,
                    ],
                ])
                return Self.response(for: url, data: data)
            case "web.ifzq.gtimg.cn":
                let data = try JSONSerialization.data(withJSONObject: [
                    "code": 0,
                    "data": [
                        "sh510300": [
                            "day": [
                                ["2026-07-17", "4.720", "4.589", "4.730", "4.546", "100"],
                                ["2026-07-20", "4.630", "4.650", "4.685", "4.577", "100"],
                                ["2026-07-21", "4.680", "4.790", "4.790", "4.620", "100"],
                            ],
                        ],
                    ],
                ])
                return Self.response(for: url, data: data)
            default:
                XCTFail("Unexpected request: \(url.absoluteString)")
                throw URLError(.unsupportedURL)
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PersonalWatchlistMockURLProtocol.self]
        let client = QiemanPlatformNativeClient(
            session: URLSession(configuration: configuration),
            now: { Self.date("2026-07-21 15:00:00") }
        )
        let records = [
            Self.record(code: "000001", category: .offExchangeFund, baseline: 1.0),
            Self.record(code: "510300", category: .onExchangeFund, baseline: 4.5),
        ]

        let snapshot = try await client.fetchPersonalWatchlistSnapshot(records: records)
        let rowsByCode = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.item.normalizedCode, $0) })
        let fund = try XCTUnwrap(rowsByCode["000001"])
        let exchange = try XCTUnwrap(rowsByCode["510300"])

        XCTAssertEqual(fund.displayName, "测试场外基金")
        XCTAssertEqual(fund.currentPrice, 1.02)
        XCTAssertEqual(fund.dailyPoints.map(\.date), ["2026-07-20", "2026-07-21"])
        XCTAssertEqual(exchange.displayName, "沪深300ETF")
        XCTAssertEqual(exchange.currentPrice, 4.787)
        XCTAssertEqual(exchange.dailyPoints.map(\.date), ["2026-07-17", "2026-07-20", "2026-07-21"])
        XCTAssertEqual(exchange.dailyPoints.last?.price, 4.787)
    }

    private static func record(
        code: String,
        category: PersonalWatchlistCategory,
        baseline: Double
    ) -> PersonalWatchlistRecord {
        PersonalWatchlistRecord(
            item: PersonalWatchlistItem(
                code: code,
                displayName: nil,
                assetType: category.assetType,
                fundMarket: category.fundMarket,
                followedAt: "2026-07-20T10:00:00Z"
            ),
            baseline: PersonalWatchlistBaseline(
                price: baseline,
                quotedAt: "2026-07-20",
                capturedAt: "2026-07-20T10:00:00Z",
                sourceLabel: "测试"
            )
        )
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

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)!
    }
}

private final class PersonalWatchlistMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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
