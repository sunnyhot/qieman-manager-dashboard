import Foundation

struct TrendAgentDetector {
    var searchPaths: [String]
    var fileManager: FileManager

    init(
        searchPaths: [String] = TrendAgentDetector.defaultSearchPaths(),
        fileManager: FileManager = .default
    ) {
        self.searchPaths = searchPaths
        self.fileManager = fileManager
    }

    func detect() -> [TrendAgentCandidate] {
        [
            candidate(kind: .claudeCLI, command: "claude", capabilities: [.nonInteractive, .jsonSchema]),
            candidate(kind: .codexCLI, command: "codex", capabilities: [.nonInteractive, .jsonSchema, .outputFile]),
            candidate(kind: .openClaw, command: "openclaw", capabilities: [.nonInteractive, .outputFile]),
            candidate(kind: .hermes, command: "hermes", capabilities: [.nonInteractive, .outputFile])
        ]
    }

    private func candidate(
        kind: TrendAgentKind,
        command: String,
        capabilities: [TrendAgentCapability]
    ) -> TrendAgentCandidate {
        let resolvedPath = resolve(command)
        let installed = resolvedPath != nil
        let executable = resolvedPath.map { fileManager.isExecutableFile(atPath: $0) } ?? false
        return TrendAgentCandidate(
            id: kind.rawValue,
            kind: kind,
            displayName: kind.displayName,
            commandPath: resolvedPath ?? command,
            version: nil,
            isInstalled: installed,
            isExecutable: executable,
            capabilities: capabilities,
            warning: installed ? nil : "未在 PATH 或常见位置检测到 \(command)"
        )
    }

    private func resolve(_ command: String) -> String? {
        for directory in searchPaths {
            let path = URL(fileURLWithPath: directory)
                .appendingPathComponent(command)
                .path
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func defaultSearchPaths() -> [String] {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let shellPaths = pathValue
            .split(separator: ":")
            .map(String.init)
        let knownPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Users/\(NSUserName())/.local/bin",
            "/Applications/Codex.app/Contents/Resources"
        ]
        var seen = Set<String>()
        return (shellPaths + knownPaths).filter { path in
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}
