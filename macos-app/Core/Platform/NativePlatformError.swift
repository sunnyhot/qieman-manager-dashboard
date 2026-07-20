import Foundation

enum NativePlatformError: LocalizedError {
    case missingProdCode
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingProdCode:
            return "没有产品代码，无法直拉平台调仓记录。"
        case .invalidResponse:
            return "平台调仓接口返回结构异常。"
        case .api(let message):
            return message
        }
    }
}
