import Foundation
import XCTest

final class TrendSkillPackTests: XCTestCase {
    func testInvestmentTrendSkillDefinesAnalysisWorkflowAndEvidenceDiscipline() throws {
        let skill = try SkillPack(root: investmentTrendSkillRoot())

        XCTAssertContains(skill.instructions, "skill/domain-rules.md")
        XCTAssertContains(skill.instructions, "skill/output-contract.md")
        XCTAssertContains(skill.domainRules, "Analysis Workflow")
        XCTAssertContains(skill.domainRules, "portfolio baseline")
        XCTAssertContains(skill.domainRules, "sector-first")
        XCTAssertContains(skill.domainRules, "manager and platform signals")
        XCTAssertContains(skill.domainRules, "Evidence Discipline")
        XCTAssertContains(skill.domainRules, "high-quality evidence")
        XCTAssertContains(skill.domainRules, "triggerConditions")
        XCTAssertContains(skill.domainRules, "invalidatingConditions")

        XCTAssertContains(skill.outputContract, "exactly three horizon objects")
        XCTAssertContains(skill.outputContract, "short")
        XCTAssertContains(skill.outputContract, "medium")
        XCTAssertContains(skill.outputContract, "long")
        XCTAssertContains(skill.outputContract, "keyAssets")
        XCTAssertContains(skill.outputContract, "rationale")
        XCTAssertContains(skill.outputContract, "counterSignals")

        XCTAssertContains(skill.examples, "\"triggerConditions\"")
        XCTAssertContains(skill.examples, "\"invalidatingConditions\"")
        XCTAssertContains(skill.examples, "\"sourceName\"")
    }

    func testTrendReportSchemaEnforcesOutputContractShape() throws {
        let skill = try SkillPack(root: investmentTrendSkillRoot())
        let schema = try skill.schemaObject()
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])

        let horizons = try XCTUnwrap(properties["horizons"] as? [String: Any])
        XCTAssertEqual(horizons["minItems"] as? Int, 3)
        XCTAssertEqual(horizons["maxItems"] as? Int, 3)
        XCTAssertNotNil(horizons["allOf"])

        let sectors = try XCTUnwrap(properties["sectors"] as? [String: Any])
        let sectorItems = try skill.itemSchema(in: sectors)
        XCTAssertEqual(Set(try XCTUnwrap(sectorItems["required"] as? [String])), [
            "name",
            "exposureText",
            "direction",
            "confidence",
            "rationale",
            "evidenceIDs",
            "counterSignals"
        ])
        XCTAssertEqual(sectorItems["additionalProperties"] as? Bool, false)

        let keyAssets = try XCTUnwrap(properties["keyAssets"] as? [String: Any])
        let keyAssetItems = try skill.itemSchema(in: keyAssets)
        XCTAssertEqual(Set(try XCTUnwrap(keyAssetItems["required"] as? [String])), [
            "name",
            "code",
            "sector",
            "impactText",
            "horizons",
            "rationale",
            "counterSignals"
        ])
        XCTAssertEqual(keyAssetItems["additionalProperties"] as? Bool, false)

        let evidence = try XCTUnwrap(properties["evidence"] as? [String: Any])
        let evidenceItems = try skill.itemSchema(in: evidence)
        XCTAssertEqual(Set(try XCTUnwrap(evidenceItems["required"] as? [String])), [
            "sourceName",
            "title",
            "url",
            "publishedAt",
            "retrievedAt",
            "summary"
        ])
        XCTAssertEqual(evidenceItems["additionalProperties"] as? Bool, false)

        let warnings = try XCTUnwrap(properties["warnings"] as? [String: Any])
        let warningItems = try skill.itemSchema(in: warnings)
        XCTAssertEqual(Set(try XCTUnwrap(warningItems["required"] as? [String])), ["title", "detail"])
        XCTAssertEqual(warningItems["additionalProperties"] as? Bool, false)
    }

    func testTrendReportSchemaRequiresMarketOpportunitiesAndAssetTrends() throws {
        let skill = try SkillPack(root: investmentTrendSkillRoot())
        let schema = try skill.schemaObject()
        let required = Set(try XCTUnwrap(schema["required"] as? [String]))
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])

        XCTAssertTrue(required.contains("marketOutlook"))
        XCTAssertTrue(required.contains("opportunities"))
        XCTAssertTrue(required.contains("assetTrends"))

        let marketOutlook = try XCTUnwrap(properties["marketOutlook"] as? [String: Any])
        let marketItems = try skill.itemSchema(in: marketOutlook)
        XCTAssertEqual(Set(try XCTUnwrap(marketItems["required"] as? [String])), [
            "name",
            "category",
            "direction",
            "confidence",
            "rationale",
            "evidenceIDs",
            "counterSignals"
        ])

        let opportunities = try XCTUnwrap(properties["opportunities"] as? [String: Any])
        let opportunityItems = try skill.itemSchema(in: opportunities)
        XCTAssertEqual(Set(try XCTUnwrap(opportunityItems["required"] as? [String])), [
            "name",
            "category",
            "direction",
            "confidence",
            "rationale",
            "triggerConditions",
            "invalidatingConditions",
            "evidenceIDs",
            "counterSignals"
        ])

        let assetTrends = try XCTUnwrap(properties["assetTrends"] as? [String: Any])
        let assetTrendItems = try skill.itemSchema(in: assetTrends)
        XCTAssertEqual(Set(try XCTUnwrap(assetTrendItems["required"] as? [String])), [
            "name",
            "code",
            "sector",
            "impactText",
            "horizons",
            "rationale",
            "counterSignals"
        ])
    }

    private func investmentTrendSkillRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("skills/investment-trend-analysis", isDirectory: true)
    }

    private func XCTAssertContains(
        _ text: String,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            text.contains(expected),
            "Expected text to contain '\(expected)'",
            file: file,
            line: line
        )
    }
}

private struct SkillPack {
    let instructions: String
    let domainRules: String
    let outputContract: String
    let examples: String
    let schema: String

    init(root: URL) throws {
        instructions = try String(contentsOf: root.appendingPathComponent("SKILL.md"))
        domainRules = try String(contentsOf: root.appendingPathComponent("references/domain-rules.md"))
        outputContract = try String(contentsOf: root.appendingPathComponent("references/output-contract.md"))
        examples = try String(contentsOf: root.appendingPathComponent("assets/examples.json"))
        schema = try String(contentsOf: root.appendingPathComponent("assets/trend-report.schema.json"))
    }

    func schemaObject() throws -> [String: Any] {
        let data = Data(schema.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func itemSchema(in arraySchema: [String: Any]) throws -> [String: Any] {
        let items = try XCTUnwrap(arraySchema["items"] as? [String: Any])
        if let ref = items["$ref"] as? String {
            let name = try XCTUnwrap(ref.split(separator: "/").last.map(String.init))
            let defs = try XCTUnwrap(schemaObject()["$defs"] as? [String: Any])
            return try XCTUnwrap(defs[name] as? [String: Any])
        }
        return items
    }
}
