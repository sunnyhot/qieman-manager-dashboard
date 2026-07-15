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
