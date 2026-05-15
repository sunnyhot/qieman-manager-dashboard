import Foundation

// MARK: - API Client

class APIClient {
    let baseURL: URL
    private(set) var token: String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    // MARK: - Generic Request Methods

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        let data = try await requestRaw(path, method: method, body: body)
        return try decoder.decode(T.self, from: data)
    }

    func requestRaw(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                throw APIError.authenticationError
            }

            if !(200..<300).contains(httpResponse.statusCode) {
                if let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data) {
                    throw APIError.serverError(errorResponse.message ?? errorResponse.error)
                }

                let errorMessage = String(data: data, encoding: .utf8) ?? "请求失败"
                throw APIError.serverError(errorMessage)
            }

            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - HTTP Method Helpers

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET")
    }

    func post<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        try await request(path, method: "POST", body: body)
    }

    func put<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        try await request(path, method: "PUT", body: body)
    }

    func patch<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        try await request(path, method: "PATCH", body: body)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "DELETE")
    }

    func deleteRaw(_ path: String) async throws {
        _ = try await requestRaw(path, method: "DELETE")
    }
}

// MARK: - Authentication API

extension APIClient {
    func sendCode(email: String) async throws {
        let body = SendCodeRequest(email: email)
        _ = try await requestRaw("api/auth/send-code", method: "POST", body: body)
    }

    func verifyCode(email: String, code: String) async throws -> LoginResponse {
        let body = VerifyCodeRequest(email: email, code: code)
        return try await request("api/auth/verify", method: "POST", body: body)
    }

    func logout() async throws {
        _ = try await requestRaw("api/auth/logout", method: "POST")
    }
}

// MARK: - Workspace API

extension APIClient {
    func listWorkspaces() async throws -> [Workspace] {
        return try await get("api/workspaces")
    }

    func getWorkspace(slug: String) async throws -> Workspace {
        return try await get("api/workspaces/\(slug)")
    }
}
