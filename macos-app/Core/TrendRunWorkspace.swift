import Foundation

struct TrendRunPacket: Hashable {
    let runDirectory: URL
    let promptURL: URL
    let contextURL: URL
    let schemaURL: URL
    let outputURL: URL
    let logURL: URL
}

struct TrendRunWorkspace {
    let rootDirectory: URL
    let skillRoot: URL
    var fileManager: FileManager = .default

    func prepare(context: TrendAnalysisContext, prompt: TrendModelPrompt) throws -> TrendRunPacket {
        let runDirectory = rootDirectory.appendingPathComponent("trend-run-\(UUID().uuidString)", isDirectory: true)
        let inputDirectory = runDirectory.appendingPathComponent("input", isDirectory: true)
        let skillDirectory = runDirectory.appendingPathComponent("skill", isDirectory: true)
        let schemaDirectory = runDirectory.appendingPathComponent("schema", isDirectory: true)
        let outputDirectory = runDirectory.appendingPathComponent("output", isDirectory: true)

        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: schemaDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let contextURL = inputDirectory.appendingPathComponent("portfolio-context.json")
        let promptURL = runDirectory.appendingPathComponent("prompt.md")
        let schemaURL = schemaDirectory.appendingPathComponent("trend-report.schema.json")
        let outputURL = outputDirectory.appendingPathComponent("trend-report.json")
        let logURL = outputDirectory.appendingPathComponent("agent-log.txt")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(context).write(to: contextURL, options: .atomic)
        try promptText(prompt)
            .write(to: promptURL, atomically: true, encoding: .utf8)

        try copySkillFile("SKILL.md", to: skillDirectory.appendingPathComponent("instructions.md"))
        try copySkillFile("references/domain-rules.md", to: skillDirectory.appendingPathComponent("domain-rules.md"))
        try copySkillFile("references/output-contract.md", to: skillDirectory.appendingPathComponent("output-contract.md"))
        try copySkillFile("assets/examples.json", to: skillDirectory.appendingPathComponent("examples.json"))
        try copySkillFile("assets/trend-report.schema.json", to: schemaURL)

        return TrendRunPacket(
            runDirectory: runDirectory,
            promptURL: promptURL,
            contextURL: contextURL,
            schemaURL: schemaURL,
            outputURL: outputURL,
            logURL: logURL
        )
    }

    private func promptText(_ prompt: TrendModelPrompt) -> String {
        """
        # System

        \(prompt.system)

        # User

        \(prompt.user)

        # Files

        - Context: input/portfolio-context.json
        - Skill instructions: skill/instructions.md
        - Domain rules: skill/domain-rules.md
        - Output contract: skill/output-contract.md
        - Examples: skill/examples.json
        - Schema: schema/trend-report.schema.json
        - Write final JSON to: output/trend-report.json
        """
    }

    private func copySkillFile(_ relativePath: String, to destination: URL) throws {
        let source = skillRoot.appendingPathComponent(relativePath)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
