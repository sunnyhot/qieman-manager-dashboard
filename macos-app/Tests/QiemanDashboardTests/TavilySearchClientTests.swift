import XCTest
@testable import QiemanDashboard

final class TavilySearchClientTests: XCTestCase {
    override func tearDown() {
        MockTavilyURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSearchEncodesRestrictedRequestAndDecodesResults() async throws {
        MockTavilyURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, TavilySearchClient.endpoint)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tvly-test")

            let body = try Self.requestBodyData(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["query"] as? String, "中国最新产业政策")
            XCTAssertEqual(json["topic"] as? String, "news")
            XCTAssertEqual(json["search_depth"] as? String, "basic")
            XCTAssertEqual(json["max_results"] as? Int, 5)
            XCTAssertEqual(json["time_range"] as? String, "week")
            XCTAssertEqual(json["include_domains"] as? [String], ["gov.cn"])
            XCTAssertEqual(json["include_answer"] as? Bool, false)
            XCTAssertEqual(json["include_raw_content"] as? Bool, false)

            let data = try JSONSerialization.data(withJSONObject: [
                "query": "中国最新产业政策",
                "results": [
                    [
                        "title": "政策发布",
                        "url": "https://www.gov.cn/zhengce/example",
                        "content": "国务院发布最新产业政策。",
                        "score": "0.92",
                        "published_date": "2026-07-23"
                    ]
                ],
                // Tavily 的接口 schema 定义为 number，文档示例曾显示为 string，两种都要兼容。
                "response_time": 0.45,
                "request_id": "request-1"
            ])
            return (Self.response(for: request, statusCode: 200), data)
        }

        let client = TavilySearchClient(session: Self.mockSession())
        let response = try await client.search(
            TavilySearchRequest(
                query: "中国最新产业政策",
                topic: "news",
                searchDepth: "basic",
                maxResults: 5,
                timeRange: "week",
                includeDomains: ["gov.cn"],
                includeAnswer: false,
                includeRawContent: false,
                includeImages: false
            ),
            apiKey: "tvly-test",
            timeoutSeconds: 10
        )

        XCTAssertEqual(response.requestID, "request-1")
        XCTAssertEqual(response.responseTime, "0.45")
        XCTAssertEqual(response.results.first?.title, "政策发布")
        XCTAssertEqual(response.results.first?.score, 0.92)
        XCTAssertEqual(response.results.first?.publishedDate, "2026-07-23")
    }

    func testSearchReportsPreciseFieldWhenSuccessfulResponseShapeIsInvalid() async throws {
        MockTavilyURLProtocol.requestHandler = { request in
            let data = try JSONSerialization.data(withJSONObject: [
                "query": "测试",
                "results": "unexpected",
                "response_time": 0.2
            ])
            return (Self.response(for: request, statusCode: 200), data)
        }

        let client = TavilySearchClient(session: Self.mockSession())
        do {
            _ = try await client.search(
                TavilySearchRequest(
                    query: "测试",
                    topic: "news",
                    searchDepth: "basic",
                    maxResults: 5,
                    timeRange: "week",
                    includeDomains: nil,
                    includeAnswer: false,
                    includeRawContent: false,
                    includeImages: false
                ),
                apiKey: "tvly-test",
                timeoutSeconds: 10
            )
            XCTFail("Expected invalid response")
        } catch let error as TavilySearchClientError {
            XCTAssertTrue(error.localizedDescription.contains("$.results"))
            XCTAssertTrue(error.localizedDescription.contains("results=string"))
        }
    }

    func testSearchMapsAuthenticationAndRateLimitErrors() async throws {
        let client = TavilySearchClient(session: Self.mockSession())
        let request = TavilySearchRequest(
            query: "测试",
            topic: "news",
            searchDepth: "basic",
            maxResults: 5,
            timeRange: "month",
            includeDomains: nil,
            includeAnswer: false,
            includeRawContent: false,
            includeImages: false
        )

        MockTavilyURLProtocol.requestHandler = { urlRequest in
            (
                Self.response(for: urlRequest, statusCode: 401),
                #"{"detail":{"error":"Unauthorized"}}"#.data(using: .utf8)!
            )
        }
        do {
            _ = try await client.search(request, apiKey: "bad-key", timeoutSeconds: 10)
            XCTFail("Expected 401")
        } catch let error as TavilySearchClientError {
            XCTAssertTrue(error.localizedDescription.contains("API Key 无效"))
            XCTAssertTrue(error.localizedDescription.contains("Unauthorized"))
        }

        MockTavilyURLProtocol.requestHandler = { urlRequest in
            (
                Self.response(for: urlRequest, statusCode: 432),
                #"{"detail":{"error":"Usage limit exceeded"}}"#.data(using: .utf8)!
            )
        }
        do {
            _ = try await client.search(request, apiKey: "tvly-test", timeoutSeconds: 10)
            XCTFail("Expected 429")
        } catch let error as TavilySearchClientError {
            XCTAssertTrue(error.localizedDescription.contains("额度"))
            XCTAssertTrue(error.localizedDescription.contains("Usage limit exceeded"))
        }
    }

    private static func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTavilyURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func requestBodyData(_ request: URLRequest) throws -> Data {
        if let httpBody = request.httpBody {
            return httpBody
        }
        guard let stream = request.httpBodyStream else {
            XCTFail("Expected request body")
            return Data()
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class MockTavilyURLProtocol: URLProtocol {
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
