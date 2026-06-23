import XCTest
@testable import QiemanDashboard

final class TrendAIClientTests: XCTestCase {
    override func tearDown() {
        MockTrendURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testClientSendsOpenAICompatibleRequestAndDecodesReport() async throws {
        let report = TrendAnalysisReport.fixture(
            generatedAt: "2026-06-22 12:00:00",
            externalSignalStatus: .available
        )
        let reportData = try JSONEncoder().encode(report)
        let reportContent = try XCTUnwrap(String(data: reportData, encoding: .utf8))
        let responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [
                [
                    "message": [
                        "content": reportContent
                    ]
                ]
            ]
        ])

        MockTrendURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = try Self.requestBodyData(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "test-model")
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTrendURLProtocol.self]
        let client = TrendAIClient(session: URLSession(configuration: configuration))

        let decoded = try await client.generateReport(
            prompt: TrendModelPrompt(system: "system prompt", user: "user prompt"),
            settings: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://api.example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 15
            )
        )

        XCTAssertEqual(decoded.generatedAt, "2026-06-22 12:00:00")
        XCTAssertEqual(decoded.externalSignalStatus, .available)
    }

    func testConnectionCheckSendsMinimalPromptAndReturnsPreview() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [
                [
                    "message": [
                        "content": "OK"
                    ]
                ]
            ]
        ])

        MockTrendURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")

            let body = try Self.requestBodyData(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "test-model")
            XCTAssertEqual(json["max_tokens"] as? Int, 16)
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
            XCTAssertEqual(messages.last?["content"], "ping")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTrendURLProtocol.self]
        let client = TrendAIClient(session: URLSession(configuration: configuration))

        let result = try await client.checkConnection(settings: TrendAIProviderSettings(
            providerName: "Test",
            baseURL: "https://api.example.com/v1",
            model: "test-model",
            apiKey: "sk-test",
            supportsOnlineSearch: true,
            timeoutSeconds: 15
        ))

        XCTAssertEqual(result.preview, "OK")
        XCTAssertEqual(result.endpoint, "https://api.example.com/v1/chat/completions")
    }

    func testMissingChoicesResponseUsesActionableError() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: [
            "id": "not-chat-completion"
        ])

        MockTrendURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, responseData)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockTrendURLProtocol.self]
        let client = TrendAIClient(session: URLSession(configuration: configuration))

        do {
            _ = try await client.checkConnection(settings: TrendAIProviderSettings(
                providerName: "Test",
                baseURL: "https://api.example.com/v1",
                model: "test-model",
                apiKey: "sk-test",
                supportsOnlineSearch: true,
                timeoutSeconds: 15
            ))
            XCTFail("Expected OpenAI-compatible response format error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("OpenAI-compatible"))
            XCTAssertTrue(error.localizedDescription.contains("choices"))
        }
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
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class MockTrendURLProtocol: URLProtocol {
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
