import Foundation

enum APIClientError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "本地服务返回了无法识别的数据。"
        case .server(let message):
            return message
        }
    }
}

final class DashboardAPIClient {
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func fetchBootstrap(baseURL: URL) async throws -> BootstrapPayload {
        try await request(
            url: baseURL.appendingPathComponent("api/bootstrap"),
            method: "GET",
            body: Optional<Data>.none
        )
    }

    func fetchHistory(baseURL: URL) async throws -> HistoryPayload {
        try await request(
            url: baseURL.appendingPathComponent("api/history"),
            method: "GET",
            body: Optional<Data>.none
        )
    }

    func fetchSnapshot(baseURL: URL, name: String) async throws -> SnapshotPayload {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/snapshot"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }
        struct SnapshotEnvelope: Decodable {
            let snapshot: SnapshotPayload
        }
        let payload: SnapshotEnvelope = try await request(url: url, method: "GET", body: Optional<Data>.none)
        return payload.snapshot
    }

    func fetchLatestSnapshot(baseURL: URL, form: QueryFormState, persist: Bool) async throws -> SnapshotPayload {
        let body = try JSONSerialization.data(withJSONObject: form.fetchPayload(persist: persist), options: [])
        let payload: FetchResponsePayload = try await request(
            url: baseURL.appendingPathComponent("api/fetch"),
            method: "POST",
            body: body
        )
        return payload.snapshot
    }

    func fetchPlatform(baseURL: URL, prodCode: String) async throws -> PlatformPayload {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/platform"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "prod_code", value: prodCode)]
        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }
        return try await request(url: url, method: "GET", body: Optional<Data>.none)
    }

    func checkAuth(baseURL: URL) async throws -> AuthCheckPayload {
        try await request(
            url: baseURL.appendingPathComponent("api/check-auth"),
            method: "GET",
            body: Optional<Data>.none
        )
    }

    func fetchComments(baseURL: URL, postID: Int, sortType: String, pageNum: Int, managerBrokerUserID: String) async throws -> CommentsPayload {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/comments"), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "post_id", value: String(postID)),
            URLQueryItem(name: "page_num", value: String(pageNum)),
            URLQueryItem(name: "page_size", value: "10"),
            URLQueryItem(name: "sort_type", value: sortType),
        ]
        if !managerBrokerUserID.isEmpty {
            items.append(URLQueryItem(name: "manager_broker_user_id", value: managerBrokerUserID))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw APIClientError.invalidResponse
        }
        return try await request(url: url, method: "GET", body: Optional<Data>.none)
    }

    private func request<T: Decodable>(url: URL, method: String, body: Data?) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            if let serverError = try? decoder.decode([String: String].self, from: data),
               let message = serverError["error"] {
                throw APIClientError.server(message)
            }
            let text = String(data: data, encoding: .utf8) ?? "请求失败"
            throw APIClientError.server(text)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.server("解析响应失败：\(error.localizedDescription)")
        }
    }
}
