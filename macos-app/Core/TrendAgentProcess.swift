import Foundation

struct TrendAgentProcessResult: Hashable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct TrendAgentProcessClient {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        standardInput: String?,
        timeoutSeconds: Double
    ) async throws -> TrendAgentProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdinPipe: Pipe?
            if standardInput != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                stdinPipe = pipe
            } else {
                stdinPipe = nil
            }

            let resumeGate = TrendAgentProcessResumeGate()

            @Sendable func finish(_ result: Result<TrendAgentProcessResult, Error>) {
                guard resumeGate.claim() else { return }
                continuation.resume(with: result)
            }

            process.terminationHandler = { terminatedProcess in
                let stdout = String(
                    data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                finish(.success(TrendAgentProcessResult(
                    exitCode: terminatedProcess.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            if let standardInput, let stdinPipe {
                DispatchQueue.global(qos: .utility).async {
                    stdinPipe.fileHandleForWriting.write(Data(standardInput.utf8))
                    try? stdinPipe.fileHandleForWriting.close()
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(1, timeoutSeconds) * 1_000_000_000))
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }
}

private final class TrendAgentProcessResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
