import XCTest
@testable import QiemanDashboard

final class DownloadProgressTests: XCTestCase {
    func testPercentTextRoundsFraction() {
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 0, totalBytes: 100, fraction: 0).percentText, "0%")
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 50, totalBytes: 100, fraction: 0.5).percentText, "50%")
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 99, totalBytes: 100, fraction: 0.99).percentText, "99%")
        XCTAssertEqual(AppSelfUpdateDownloadProgress(bytesReceived: 999, totalBytes: 1_000, fraction: 0.999).percentText, "100%")
    }

    func testSizeTextIncludesTotalWhenTotalBytesAreKnown() {
        let progress = AppSelfUpdateDownloadProgress(bytesReceived: 1_024, totalBytes: 2_048, fraction: 0.5)

        XCTAssertTrue(progress.sizeText.contains("/"), progress.sizeText)
        XCTAssertFalse(progress.sizeText.isEmpty)
    }

    func testSizeTextOmitsTotalWhenTotalBytesAreUnknown() {
        let progress = AppSelfUpdateDownloadProgress(bytesReceived: 1_024, totalBytes: 0, fraction: 0)

        XCTAssertFalse(progress.sizeText.contains("/"), progress.sizeText)
        XCTAssertFalse(progress.sizeText.isEmpty)
    }
}
