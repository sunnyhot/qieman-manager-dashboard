import Foundation

// MARK: - User Model

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let name: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Workspace Model

struct Workspace: Codable, Identifiable {
    let id: String
    let name: String
    let slug: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Login Response

struct LoginResponse: Codable {
    let token: String
    let user: User
}

// MARK: - Send Code Request

struct SendCodeRequest: Codable {
    let email: String
}

// MARK: - Verify Code Request

struct VerifyCodeRequest: Codable {
    let email: String
    let code: String
}

// MARK: - API Error Response

struct APIErrorResponse: Codable {
    let error: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case networkError(Error)
    case authenticationError
    case tokenExpired
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回了无法识别的数据"
        case .serverError(let message):
            return message
        case .networkError(let error):
            return "网络连接失败：\(error.localizedDescription)"
        case .authenticationError:
            return "认证失败，请重新登录"
        case .tokenExpired:
            return "登录已过期，请重新登录"
        case .invalidCredentials:
            return "验证码错误或已过期"
        }
    }
}