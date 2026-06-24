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

    init(root: URL) throws {
        instructions = try String(contentsOf: root.appendingPathComponent("SKILL.md"))
        domainRules = try String(contentsOf: root.appendingPathComponent("references/domain-rules.md"))
        outputContract = try String(contentsOf: root.appendingPathComponent("references/output-contract.md"))
        examples = try String(contentsOf: root.appendingPathComponent("assets/examples.json"))
    }
}
