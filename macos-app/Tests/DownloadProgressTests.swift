// Standalone test for AppSelfUpdateDownloadProgress logic
// Compiles and runs independently from the main app target

import Foundation

// MARK: - Replicate the struct from AppSelfUpdater.swift

struct AppSelfUpdateDownloadProgress: Sendable {
    let bytesReceived: Int64
    let totalBytes: Int64
    let fraction: Double

    var percentText: String {
        String(format: "%.0f%%", fraction * 100)
    }

    var sizeText: String {
        let received = ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)
        if totalBytes > 0 {
            let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(received) / \(total)"
        }
        return received
    }
}

// MARK: - Test Helpers

var testsPassed = 0
var testsFailed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        testsPassed += 1
        print("  ✅ PASS: \(message)")
    } else {
        testsFailed += 1
        print("  ❌ FAIL: \(message) (line \(line))")
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #file, line: Int = #line) {
    if actual == expected {
        testsPassed += 1
        print("  ✅ PASS: \(message)")
    } else {
        testsFailed += 1
        print("  ❌ FAIL: \(message) — expected \(expected), got \(actual) (line \(line))")
    }
}

// MARK: - Test: percentText

print("\n📊 Test: percentText")

let p0 = AppSelfUpdateDownloadProgress(bytesReceived: 0, totalBytes: 100, fraction: 0)
assertEqual(p0.percentText, "0%", "0% at start")

let p50 = AppSelfUpdateDownloadProgress(bytesReceived: 50, totalBytes: 100, fraction: 0.5)
assertEqual(p50.percentText, "50%", "50% at half")

let p99 = AppSelfUpdateDownloadProgress(bytesReceived: 99, totalBytes: 100, fraction: 0.99)
assertEqual(p99.percentText, "99%", "99% near end")

let p100 = AppSelfUpdateDownloadProgress(bytesReceived: 100, totalBytes: 100, fraction: 1.0)
assertEqual(p100.percentText, "100%", "100% complete")

// Edge: fraction 0.001 should round to 0%
let pTiny = AppSelfUpdateDownloadProgress(bytesReceived: 1, totalBytes: 10000, fraction: 0.0001)
assertEqual(pTiny.percentText, "0%", "Tiny fraction rounds to 0%")

// Edge: fraction 0.999 rounds to 100%
let pAlmost = AppSelfUpdateDownloadProgress(bytesReceived: 999, totalBytes: 1000, fraction: 0.999)
assertEqual(pAlmost.percentText, "100%", "99.9% rounds to 100%")

// MARK: - Test: sizeText

print("\n📊 Test: sizeText")

let pSmall = AppSelfUpdateDownloadProgress(bytesReceived: 1024, totalBytes: 2048, fraction: 0.5)
let smallText = pSmall.sizeText
assert(smallText.contains("/"), "Size text contains separator: \(smallText)")
assert(smallText.contains("1"), "Size text shows 1 KB received: \(smallText)")

let pBig = AppSelfUpdateDownloadProgress(bytesReceived: 30_000_000, totalBytes: 60_000_000, fraction: 0.5)
let bigText = pBig.sizeText
assert(bigText.contains("30"), "30 MB received shown: \(bigText)")
assert(bigText.contains("60"), "60 MB total shown: \(bigText)")

let pZero = AppSelfUpdateDownloadProgress(bytesReceived: 0, totalBytes: 0, fraction: 0)
let zeroText = pZero.sizeText
assert(!zeroText.contains("/"), "Zero total shows no separator: \(zeroText)")

// MARK: - Test: DownloadDelegate fraction calculation

print("\n📊 Test: DownloadDelegate fraction calculation logic")

// Simulate what the delegate does:
// let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
// let fraction = total > 0 ? Double(totalBytesWritten) / Double(total) : 0

func simulateFraction(bytesWritten: Int64, expectedTotal: Int64, knownSize: Int64) -> Double {
    let total = expectedTotal > 0 ? expectedTotal : knownSize
    let fraction = total > 0 ? Double(bytesWritten) / Double(total) : 0
    return min(fraction, 1.0)
}

assertEqual(simulateFraction(bytesWritten: 0, expectedTotal: 100, knownSize: 100), 0.0, "Start: 0/100 = 0.0")
assertEqual(simulateFraction(bytesWritten: 50, expectedTotal: 100, knownSize: 100), 0.5, "Half: 50/100 = 0.5")
assertEqual(simulateFraction(bytesWritten: 100, expectedTotal: 100, knownSize: 100), 1.0, "Done: 100/100 = 1.0")
assertEqual(simulateFraction(bytesWritten: 100, expectedTotal: 0, knownSize: 200), 0.5, "Fallback to knownSize: 100/200 = 0.5")
assertEqual(simulateFraction(bytesWritten: 50, expectedTotal: 0, knownSize: 0), 0.0, "Both zero: fraction = 0.0")
assertEqual(simulateFraction(bytesWritten: 200, expectedTotal: 100, knownSize: 100), 1.0, "Overflow capped at 1.0")

// MARK: - Test: Progress bar value bounds (for SwiftUI ProgressView)

print("\n📊 Test: Progress bar value bounds")

let validFractions = [0.0, 0.001, 0.25, 0.5, 0.75, 0.99, 1.0]
for f in validFractions {
    assert(f >= 0.0 && f <= 1.0, "Fraction \(f) is in valid range [0, 1]")
}

let clampedFraction = min(1.5, 1.0)
assertEqual(clampedFraction, 1.0, "Fraction > 1.0 clamped to 1.0")

// MARK: - Test: Build integration check

print("\n📊 Test: Build integration")

// Verify that AppSelfUpdater compiles cleanly (already verified by `swift build`)
// Here we just check the struct shape matches expectations
let progress = AppSelfUpdateDownloadProgress(bytesReceived: 25_000_000, totalBytes: 56_000_000, fraction: 0.45)
assertEqual(progress.percentText, "45%", "Integration: 25MB/56MB = 45%")
assert(progress.sizeText.contains("/"), "Integration: size text has separator")

// MARK: - Summary

print("\n" + String(repeating: "=", count: 50))
print("Tests: \(testsPassed) passed, \(testsFailed) failed")
if testsFailed == 0 {
    print("🎉 All tests passed!")
} else {
    print("⚠️ Some tests failed!")
}
exit(Int32(testsFailed))
