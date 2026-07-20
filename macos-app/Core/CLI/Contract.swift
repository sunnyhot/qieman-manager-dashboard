import Foundation

// MARK: - CLI output contract

/// CLI 输出契约的统一入口：所有命令的 DTO 通过这里编码为 JSON 字节。
///
/// 设计要点：
/// - `keyEncodingStrategy = .convertToSnakeCase`：DTO 属性用驼峰命名，
///   编码时自动转为 snake_case，与现有 CLI 契约字段一致。
/// - `outputFormatting = [.prettyPrinted, .sortedKeys]`：与原 `JSONSerialization`
///   行为对齐，保证快照测试稳定、diff 友好。
/// - DTO 从 App 模型显式构造，不复用 App 模型的 Codable——这样 App 模型
///   演进不会破坏 CLI 契约。
enum QiemanCLI {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// 与 `encoder` 对称的解码器：snake_case JSON → camelCase 属性。
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// 将任意 Encodable DTO 编码为 JSON Data。
    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    /// 将 JSON Data 解码为指定 Decodable 类型。
    static func decodeJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

// MARK: - NullDouble

/// 保留 "null vs 0" 语义的 Double 包装。
///
/// 原 `valuation` 命令通过 `JSONValue(_:)` 返回 `NSNull()` 表示缺失值，
/// 与 `0` 含义不同。该类型在 Codable 路径下复现这一行为：
/// - `nil`  → 输出 JSON `null`
/// - `some` → 输出数值
///
/// 默认 Codable 对 `Optional` 会跳过键，不符合现有契约，故需此显式包装。
struct NullDouble: Codable, Equatable {
    let value: Double?

    init(_ value: Double?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = nil
        } else {
            self.value = try container.decode(Double.self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}
