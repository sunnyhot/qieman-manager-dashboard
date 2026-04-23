import AppKit
import Darwin
import Foundation

enum LocalServerError: LocalizedError {
    case projectMissing
    case pythonMissing(String)
    case noPort
    case startupFailed(String)
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .projectMissing:
            return "未找到内置项目目录，请重新构建 mac App。"
        case .pythonMissing(let path):
            return "未找到可执行 Python：\(path)"
        case .noPort:
            return "没有可用端口可用于启动本地服务。"
        case .startupFailed(let message):
            return "启动本地服务失败：\(message)"
        case .unreachable(let url):
            return "本地服务未能就绪：\(url)"
        }
    }
}

final class LocalServerController {
    private let host = "127.0.0.1"
    private let defaultPort = 8765
    private let logQueue = DispatchQueue(label: "qieman.native.server.log.queue")

    private(set) var activePort = 8765
    private(set) var supportDirectory: URL?
    private(set) var projectDirectory: URL?
    private(set) var isReusingExistingServer = false

    private var logHandle: FileHandle?
    private var serverProcess: Process?

    var baseURL: URL {
        URL(string: "http://\(host):\(activePort)")!
    }

    var dataDirectoryURL: URL? {
        supportDirectory
    }

    var logFileURL: URL? {
        supportDirectory?.appendingPathComponent("dashboard.log", isDirectory: false)
    }

    var cookieFileURL: URL? {
        supportDirectory?.appendingPathComponent("qieman.cookie", isDirectory: false)
    }

    deinit {
        stopServer()
        closeLog()
    }

    @discardableResult
    func prepareEnvironment() throws -> URL {
        let projectDirectory = try resolveProjectDirectory()
        self.projectDirectory = projectDirectory
        let supportDirectory = try prepareSupportDirectory()
        self.supportDirectory = supportDirectory
        try setupLogFile()
        try seedBundledBackupIfNeeded(projectDirectory: projectDirectory, supportDirectory: supportDirectory)
        return supportDirectory
    }

    func ensureStarted() async throws -> URL {
        if isReachable(baseURL: baseURL) {
            return baseURL
        }

        let supportDirectory = try prepareEnvironment()
        guard let projectDirectory = projectDirectory else {
            throw LocalServerError.projectMissing
        }

        let existingURL = URL(string: "http://\(host):\(defaultPort)")!
        if isReachable(baseURL: existingURL) {
            activePort = defaultPort
            isReusingExistingServer = true
            appendLog("复用已存在的本地服务：\(existingURL.absoluteString)")
            return existingURL
        }

        guard let port = chooseLaunchPort(preferred: defaultPort) else {
            throw LocalServerError.noPort
        }
        activePort = port
        isReusingExistingServer = false
        try startServer(projectDirectory: projectDirectory, supportDirectory: supportDirectory, port: port)

        let targetURL = URL(string: "http://\(host):\(port)")!
        for _ in 0..<100 {
            if isReachable(baseURL: targetURL) {
                appendLog("原生 App 已连接本地服务：\(targetURL.absoluteString)")
                return targetURL
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw LocalServerError.unreachable(targetURL.absoluteString)
    }

    func openDataDirectory() {
        guard let supportDirectory else { return }
        NSWorkspace.shared.open(supportDirectory)
    }

    func openBackupInBrowser() {
        NSWorkspace.shared.open(baseURL)
    }

    private func resolveProjectDirectory() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let envPath = env["QIEMAN_PROJECT_DIR"], !envPath.isEmpty {
            let candidate = URL(fileURLWithPath: envPath, isDirectory: true)
            if hasDashboardServer(at: candidate) {
                return candidate
            }
        }

        if let resource = Bundle.main.resourceURL {
            let embedded = resource.appendingPathComponent("project", isDirectory: true)
            if hasDashboardServer(at: embedded) {
                return embedded
            }
        }

        throw LocalServerError.projectMissing
    }

    private func hasDashboardServer(at directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("dashboard_server.py").path)
    }

    private func prepareSupportDirectory() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LocalServerError.startupFailed("无法定位 Application Support 目录")
        }
        let support = appSupport.appendingPathComponent("QiemanDashboard", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try fm.createDirectory(at: support.appendingPathComponent("output", isDirectory: true), withIntermediateDirectories: true)

        let readme = support.appendingPathComponent("README.txt", isDirectory: false)
        if !fm.fileExists(atPath: readme.path) {
            let text = """
            Qieman Dashboard App 数据目录

            - qieman.cookie: 登录态 Cookie（可选）
            - output/: 历史快照与抓取结果
            - dashboard.log: 应用运行日志
            """
            try text.write(to: readme, atomically: true, encoding: .utf8)
        }
        return support
    }

    private func setupLogFile() throws {
        guard let logFileURL else { return }
        if logHandle != nil {
            return
        }
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logFileURL)
        handle.seekToEndOfFile()
        logHandle = handle
    }

    private func closeLog() {
        logQueue.sync {
            self.logHandle?.closeFile()
            self.logHandle = nil
        }
    }

    private func seedBundledBackupIfNeeded(projectDirectory: URL, supportDirectory: URL) throws {
        let fm = FileManager.default
        let targetOutput = supportDirectory.appendingPathComponent("output", isDirectory: true)
        let existingFiles = try fm.contentsOfDirectory(
            at: targetOutput,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        if existingFiles.contains(where: { $0.pathExtension == "json" || $0.pathExtension == "md" }) {
            return
        }

        let bundledOutput = projectDirectory.appendingPathComponent("output", isDirectory: true)
        guard fm.fileExists(atPath: bundledOutput.path) else {
            return
        }

        let bundledFiles = try fm.contentsOfDirectory(
            at: bundledOutput,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var importedCount = 0
        for fileURL in bundledFiles {
            let name = fileURL.lastPathComponent
            if name.hasPrefix("watch-state-") {
                continue
            }
            guard ["json", "md"].contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            let destination = targetOutput.appendingPathComponent(name, isDirectory: false)
            if fm.fileExists(atPath: destination.path) {
                continue
            }
            try fm.copyItem(at: fileURL, to: destination)
            importedCount += 1
        }

        if importedCount > 0 {
            appendLog("首次启动已导入内置备份快照 \(importedCount) 份")
        }
    }

    private func appendLog(_ line: String) {
        let data = Data((line + "\n").utf8)
        logQueue.sync {
            guard let handle = self.logHandle else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.synchronizeFile()
        }
    }

    private func startServer(projectDirectory: URL, supportDirectory: URL, port: Int) throws {
        let scriptURL = projectDirectory.appendingPathComponent("dashboard_server.py")
        let env = ProcessInfo.processInfo.environment
        let pythonPath = env["QIEMAN_PYTHON"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin/python3"

        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw LocalServerError.pythonMissing(pythonPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            scriptURL.path,
            "--host", host,
            "--port", String(port),
        ]
        process.currentDirectoryURL = projectDirectory

        var childEnv = env
        childEnv["PYTHONUNBUFFERED"] = "1"
        childEnv["QIEMAN_DATA_DIR"] = supportDirectory.path
        childEnv["QIEMAN_OUTPUT_DIR"] = supportDirectory.appendingPathComponent("output", isDirectory: true).path
        childEnv["QIEMAN_COOKIE_FILE"] = supportDirectory.appendingPathComponent("qieman.cookie", isDirectory: false).path
        process.environment = childEnv

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            self?.logQueue.sync {
                guard let logHandle = self?.logHandle else { return }
                logHandle.seekToEndOfFile()
                logHandle.write(data)
                logHandle.synchronizeFile()
            }
        }

        process.terminationHandler = { [weak self] process in
            self?.appendLog("本地服务已退出，退出码：\(process.terminationStatus)")
        }

        do {
            try process.run()
        } catch {
            throw LocalServerError.startupFailed(error.localizedDescription)
        }

        serverProcess = process
        appendLog("启动原生 App 内置服务：http://\(host):\(port)")
    }

    private func stopServer() {
        guard let process = serverProcess else { return }
        if process.isRunning {
            process.terminate()
        }
        serverProcess = nil
    }

    private func isReachable(baseURL: URL) -> Bool {
        let session = URLSession(configuration: .ephemeral)
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        var request = URLRequest(url: baseURL.appendingPathComponent("api/status"))
        request.timeoutInterval = 1
        let task = session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                ok = (200..<300).contains(http.statusCode)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.5)
        task.cancel()
        return ok
    }

    private func chooseLaunchPort(preferred: Int) -> Int? {
        if isPortBindable(preferred) {
            return preferred
        }
        for candidate in (preferred + 1)...(preferred + 50) {
            if isPortBindable(candidate) {
                appendLog("默认端口 \(preferred) 被占用，切换到 \(candidate)")
                return candidate
            }
        }
        return nil
    }

    private func isPortBindable(_ port: Int) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        if socketDescriptor < 0 {
            return false
        }
        defer { close(socketDescriptor) }

        var optionValue: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &optionValue, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr(host))

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                Darwin.bind(socketDescriptor, pointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        return result == 0
    }
}
