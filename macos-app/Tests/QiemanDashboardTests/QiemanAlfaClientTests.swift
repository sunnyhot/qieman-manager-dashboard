import Foundation
import XCTest
@testable import QiemanDashboard

/// alfa 投顾客户端测试：签名算法、拍平映射（groups/parts → actions）、store CRUD。
final class QiemanAlfaClientTests: XCTestCase {

    // MARK: - 签名算法

    func testXSign格式为时间戳加32位大写hex() {
        let sign = QiemanRequestSigning.makeXSign()
        XCTAssertEqual(sign.count, 45, "x-sign 应为 13位时间戳 + 32位hex")
        let tsPart = String(sign.prefix(13))
        XCTAssertNotNil(Int(tsPart), "前13位应为毫秒时间戳")
        let hashPart = String(sign.dropFirst(13))
        XCTAssertEqual(hashPart.count, 32, "后32位应为 hex")
        XCTAssertEqual(hashPart, hashPart.uppercased(), "hash 部分应为大写")
        // 只含 hex 字符
        XCTAssertNotNil(hashPart.range(of: "^[0-9A-F]{32}$", options: .regularExpression))
    }

    func testXSign不依赖调用时机外的随机性且格式稳定() {
        // 同一时刻多次生成的 sign 前13位（时间戳）应一致或递增
        let s1 = QiemanRequestSigning.makeXSign()
        let ts1 = Int(s1.prefix(13))!
        usleep(1000)
        let s2 = QiemanRequestSigning.makeXSign()
        let ts2 = Int(s2.prefix(13))!
        XCTAssertGreaterThanOrEqual(ts2, ts1)
    }

    func testXRequestID含前缀() {
        let id1 = QiemanRequestSigning.makeXRequestID(prefix: "zeus.")
        XCTAssertTrue(id1.hasPrefix("zeus."))
        XCTAssertEqual(id1.count, 25, "zeus.(20位hex) = 25字符")

        let id2 = QiemanRequestSigning.makeXRequestID(prefix: "albus.")
        XCTAssertTrue(id2.hasPrefix("albus."))
    }

    // MARK: - 百分比 → side 推导

    func testDeriveSide加仓() {
        XCTAssertEqual(QiemanAlfaClient.deriveSide(before: 0, after: 0.05), "buy")
        XCTAssertEqual(QiemanAlfaClient.deriveSide(before: 0.1, after: 0.15), "buy")
    }

    func testDeriveSide减仓() {
        XCTAssertEqual(QiemanAlfaClient.deriveSide(before: 0.05, after: 0), "sell")
        XCTAssertEqual(QiemanAlfaClient.deriveSide(before: 0.2, after: 0.1), "sell")
    }

    func testDeriveSide持平或缺值() {
        XCTAssertEqual(QiemanAlfaClient.deriveSide(before: 0.1, after: 0.1), "hold")
        XCTAssertEqual(QiemanAlfaClient.deriveSide(before: nil, after: 0.1), "hold")
        XCTAssertEqual(QiemanAlfaClient.deriveSide(before: 0.1, after: nil), "hold")
    }

    // MARK: - 拍平映射

    /// 构造模拟的 GraphQL Adjustment 响应（含 1 个调仓批次、1 个 group、2 个 parts）。
    private func mockAdjustmentData() -> [String: Any] {
        let part1: [String: Any] = [
            "fund": ["fundCode": "019125", "fundName": "博道红利智航股票"],
            "beforePercent": 0,
            "afterPercent": 0.015,
        ]
        let part2: [String: Any] = [
            "fund": ["fundCode": "270048", "fundName": "广发纯债债券A"],
            "beforePercent": 0.0502,
            "afterPercent": 0.0402,
        ]
        let group: [String: Any] = [
            "movementName": "权益",
            "parts": [part1, part2],
        ]
        let adjustment: [String: Any] = [
            "adjustmentId": 1726519,
            "date": "2026-07-06T00:00:00+08:00",
            "comment": "按照资产性价比模型最新数据，小幅提升红利资产仓位",
            "article": ["text": "调仓说明", "link": "https://qieman.com/content/123"],
            "groups": [group],
        ]
        return [
            "portfolio": [
                "adjustments": [
                    "adjustments": [adjustment],
                    "totalCount": 1,
                ],
            ],
        ]
    }

    func testFlattenAdjustments拍平groups和Parts() {
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "ZH158735", data: mockAdjustmentData())
        XCTAssertEqual(payload.prodCode, "ZH158735")
        XCTAssertEqual(payload.count, 2, "2 个 part → 2 条 action")
        XCTAssertEqual(payload.adjustmentCount, 1)
        XCTAssertNotNil(payload.latest)
    }

    func testFlattenAdjustments正确推导Side和百分比() {
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "X", data: mockAdjustmentData())
        let actions = payload.actions ?? []

        // part1: 0 → 0.015 = 加仓(buy)
        let buy = actions.first { $0.fundCode == "019125" }
        XCTAssertNotNil(buy)
        XCTAssertEqual(buy?.side, "buy")
        XCTAssertEqual(buy?.beforePercent, 0)
        XCTAssertEqual(buy?.afterPercent, 0.015)
        XCTAssertEqual(buy?.groupName, "权益")
        XCTAssertEqual(buy?.adjustmentId, 1726519)
        XCTAssertEqual(buy?.txnDate, "2026-07-06")

        // part2: 0.0502 → 0.0402 = 减仓(sell)
        let sell = actions.first { $0.fundCode == "270048" }
        XCTAssertNotNil(sell)
        XCTAssertEqual(sell?.side, "sell")
        XCTAssertEqual(sell?.adjustmentTitle, "按照资产性价比模型最新数据，小幅提升红利资产仓位")
        XCTAssertEqual(sell?.articleUrl, "https://qieman.com/content/123")
    }

    func testFlattenAdjustments设置sourcePoCode() {
        // 拍平后每个 action 应带来源组合码（汇总筛选用）
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "ZH158735", data: mockAdjustmentData())
        for action in payload.actions ?? [] {
            XCTAssertEqual(action.sourcePoCode, "ZH158735")
        }
    }

    func testFlattenAdjustments统计买卖数() {
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "X", data: mockAdjustmentData())
        XCTAssertEqual(payload.buyCount, 1)
        XCTAssertEqual(payload.sellCount, 1)
    }

    func testFlattenAdjustments空数据() {
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "SI000192", data: ["portfolio": [:]])
        XCTAssertEqual(payload.count, 0)
        XCTAssertNil(payload.latest)
        XCTAssertTrue(payload.supported)
    }

    func testFlattenAdjustments无Groups的批次被跳过() {
        // 有 adjustmentId 但 groups 为空 → 不计入 adjustmentCount
        let data: [String: Any] = [
            "portfolio": [
                "adjustments": [
                    "adjustments": [
                        ["adjustmentId": 1, "date": "2026-01-01", "comment": "c", "groups": []],
                    ],
                ],
            ],
        ]
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "X", data: data)
        XCTAssertEqual(payload.count, 0)
        XCTAssertEqual(payload.adjustmentCount, 0)
    }

    func testPercentText格式() {
        XCTAssertEqual(QiemanAlfaClient.percentText(before: 0, after: 0.05), "0.00%→5.00%")
        XCTAssertEqual(QiemanAlfaClient.percentText(before: nil, after: nil), "—→—")
    }

    func testPercentText单边显示() {
        // DetailCard 用单边显示调仓前/后
        XCTAssertEqual(QiemanAlfaClient.percentText(before: 0.0502, after: nil), "5.02%→—")
        XCTAssertEqual(QiemanAlfaClient.percentText(before: nil, after: 0.0402), "—→4.02%")
    }

    func testFlattenActionsIsPercentBased标记() {
        // 拍平后的 action 必须标记 isPercentBased=true（UI 渲染依赖）
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "X", data: mockAdjustmentData())
        for action in payload.actions ?? [] {
            XCTAssertTrue(action.isPercentBased, "alfa action 应标记 isPercentBased=true")
            XCTAssertNotNil(action.beforePercent)
            XCTAssertNotNil(action.afterPercent)
        }
    }

    func testFlattenActionsActionTitle含百分比() {
        // actionTitle 用于显示，应包含百分比文本
        let payload = QiemanAlfaClient.flattenAdjustments(poCode: "X", data: mockAdjustmentData())
        let buy = payload.actions?.first { $0.fundCode == "019125" }
        XCTAssertNotNil(buy)
        XCTAssertTrue(buy!.actionTitle!.contains("0.00%→1.50%"), "actionTitle 应含百分比，实际：\(buy!.actionTitle!)")
    }

    // MARK: - AlfaPortfolioStore

    func testStore默认预置晓磊() {
        let defaults = AlfaPortfolioStore.defaultPortfolios
        XCTAssertTrue(defaults.contains { $0.poCode == "SI000192" })
        XCTAssertEqual(defaults.first?.name, "基金全磊打之大航海时代")
    }

    func testStore读写持久化() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("alfa-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = AlfaPortfolioStore()
        var items = AlfaPortfolioStore.defaultPortfolios
        items.append(AlfaPortfolioCatalogItem(poCode: "ZH032687", name: "风和日丽", author: "盈米基金", category: "长钱"))

        try store.save(items, to: tmp)
        let loaded = store.load(from: tmp)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.last?.poCode, "ZH032687")
    }

    func testStore缺失文件返回默认() {
        let nonexistent = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let store = AlfaPortfolioStore()
        let loaded = store.load(from: nonexistent)
        XCTAssertEqual(loaded, AlfaPortfolioStore.defaultPortfolios)
    }
}
