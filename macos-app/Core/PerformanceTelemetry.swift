import Foundation
import os

struct PerformanceTelemetryEvent: Equatable {
    let name: String
    let elapsedMilliseconds: Double
    let metadata: [String: String]

    var message: String {
        let base = "\(name) \(String(format: "%.1f", elapsedMilliseconds))ms"
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(Self.safeMetadataValue(key: key, value: value))"
            }
            .joined(separator: " ")
        return metadataText.isEmpty ? base : "\(base) \(metadataText)"
    }

    private static func safeMetadataValue(key: String, value: String) -> String {
        if isSensitive(key) || isSensitive(value) {
            return "<redacted>"
        }
        if value.count > 80 {
            return String(value.prefix(77)) + "..."
        }
        return value
    }

    private static func isSensitive(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains("cookie")
            || lowercased.contains("authorization")
            || lowercased.contains("token")
    }
}

enum PerformanceTelemetry {
    typealias EventSink = (PerformanceTelemetryEvent) -> Void

    private static let lock = NSLock()
    private static var eventSink: EventSink?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.sunnyhot.qieman.manager.dashboard",
        category: "performance"
    )

    static func start() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func record(
        _ name: String,
        startedAt startTime: UInt64,
        metadata: [String: String] = [:]
    ) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000.0
        emit(PerformanceTelemetryEvent(name: name, elapsedMilliseconds: elapsed, metadata: metadata))
    }

    @discardableResult
    static func measure<T>(
        _ name: String,
        metadata: [String: String] = [:],
        operation: () throws -> T
    ) rethrows -> T {
        let startedAt = start()
        defer { record(name, startedAt: startedAt, metadata: metadata) }
        return try operation()
    }

    @discardableResult
    static func measureAsync<T>(
        _ name: String,
        metadata: [String: String] = [:],
        operation: () async throws -> T
    ) async rethrows -> T {
        let startedAt = start()
        defer { record(name, startedAt: startedAt, metadata: metadata) }
        return try await operation()
    }

    @discardableResult
    static func withSink<T>(_ sink: @escaping EventSink, run: () throws -> T) rethrows -> T {
        let previousSink = swapSink(sink)
        defer { _ = swapSink(previousSink) }
        return try run()
    }

    @discardableResult
    static func withSink<T>(_ sink: @escaping EventSink, run: () async throws -> T) async rethrows -> T {
        let previousSink = swapSink(sink)
        defer { _ = swapSink(previousSink) }
        return try await run()
    }

    private static func swapSink(_ sink: EventSink?) -> EventSink? {
        lock.lock()
        defer { lock.unlock() }
        let previous = eventSink
        eventSink = sink
        return previous
    }

    private static func currentSink() -> EventSink? {
        lock.lock()
        defer { lock.unlock() }
        return eventSink
    }

    private static func emit(_ event: PerformanceTelemetryEvent) {
        if let sink = currentSink() {
            sink(event)
            return
        }
        guard shouldLogToOS else { return }
        logger.info("[perf] \(event.message, privacy: .public)")
    }

    private static var shouldLogToOS: Bool {
        ProcessInfo.processInfo.environment["QIEMAN_PERF_LOG"] == "1"
            || _isDebugAssertConfiguration()
    }
}
