import XCTest
@testable import QiemanDashboard

final class QiemanCookieManagerTests: XCTestCase {
    func testPersistCookieHeaderWritesOwnerOnlyPermissions() throws {
        let cookieURL = try temporaryCookieURL()
        let manager = QiemanCookieManager(cookieFileURL: cookieURL)

        try manager.persistCookieHeader("access_token=abc; qm=test")

        XCTAssertEqual(try posixPermissions(at: cookieURL), 0o600)
    }

    func testLoadCookieStringTightensExistingReadableCookieFile() throws {
        let cookieURL = try temporaryCookieURL()
        try FileManager.default.createDirectory(at: cookieURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "access_token=abc".write(to: cookieURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cookieURL.path)
        let manager = QiemanCookieManager(cookieFileURL: cookieURL)

        XCTAssertEqual(try manager.loadCookieString(), "access_token=abc")

        XCTAssertEqual(try posixPermissions(at: cookieURL), 0o600)
    }

    private func temporaryCookieURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qieman-cookie-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("qieman.cookie", isDirectory: false)
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return value.intValue
    }
}
