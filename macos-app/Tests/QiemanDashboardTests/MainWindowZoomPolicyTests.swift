import XCTest
@testable import QiemanDashboard

final class MainWindowZoomPolicyTests: XCTestCase {
    func testUnifiedToolbarBandAcceptsClicksBelowNativeTitlebarHeight() {
        let contentHeight: CGFloat = 800
        let nativeTitlebarHeight: CGFloat = 28

        XCTAssertTrue(
            MainWindowZoomPolicy.isInDoubleClickZoomBand(
                clickY: 730,
                contentHeight: contentHeight,
                nativeTitlebarHeight: nativeTitlebarHeight
            )
        )
    }

    func testContentAreaBelowToolbarBandIsNotZoomRegion() {
        XCTAssertFalse(
            MainWindowZoomPolicy.isInDoubleClickZoomBand(
                clickY: 680,
                contentHeight: 800,
                nativeTitlebarHeight: 28
            )
        )
    }
}
