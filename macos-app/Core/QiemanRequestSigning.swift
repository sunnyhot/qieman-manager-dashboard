import CryptoKit
import Foundation

/// 且慢平台请求签名工具。
///
/// `x-sign` / `x-request-id` 的算法在 `QiemanNativeClient` 与
/// `QiemanPlatformNativeClient` 中各有一份拷贝，这里抽出来统一维护。
/// 新的 alfa 投顾客户端（GraphQL）也复用同一套签名。
enum QiemanRequestSigning {

    /// SHA256 十六进制摘要（小写）。
    static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 生成 `x-sign`：`{13位毫秒时间戳}{sha256(floor(1.01*ts)) 前32位大写}`。
    /// 签名仅依赖时间戳，与请求体无关，同一时刻的任意请求可共用。
    static func makeXSign(now: Date = Date()) -> String {
        let ts = Int(now.timeIntervalSince1970 * 1000)
        let digest = sha256Hex(String(Int(Double(ts) * 1.01))).uppercased()
        return "\(ts)\(digest.prefix(32))"
    }

    /// 生成 `x-request-id`：`{prefix}{sha256(random+ts+pathWithQuery+anonymousID) 后20位大写}`。
    /// - Parameters:
    ///   - prefix: 客户端前缀。社区/平台接口用 `"albus."`，alfa 投顾线用 `"zeus."`。
    ///   - pathWithQuery: 请求路径（含 query），混入随机种子增加熵。
    ///   - anonymousID: 匿名标识，混入随机种子。
    static func makeXRequestID(
        prefix: String,
        pathWithQuery: String = "",
        anonymousID: String = "",
        now: Date = Date()
    ) -> String {
        let ts = Int(now.timeIntervalSince1970 * 1000)
        let seed = "\(Double.random(in: 0..<1))\(ts)\(pathWithQuery)\(anonymousID)"
        return "\(prefix)\(sha256Hex(seed).suffix(20).uppercased())"
    }
}
