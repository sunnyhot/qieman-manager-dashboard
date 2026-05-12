import XCTest
@testable import QiemanDashboard

final class SidebarChromeMetricsTests: XCTestCase {
    func testExpandedToggleSitsNearSidebarTrailingEdge() {
        let x = SidebarChromeMetrics.toggleOriginX(
            isSidebarCollapsed: false,
            expandedSidebarWidth: 232,
            toggleWidth: 70,
            trafficLightRightX: 74
        )

        XCTAssertEqual(x, 146)
    }

    func testCollapsedToggleFallsBackAfterTrafficLights() {
        let x = SidebarChromeMetrics.toggleOriginX(
            isSidebarCollapsed: true,
            expandedSidebarWidth: 232,
            toggleWidth: 70,
            trafficLightRightX: 74
        )

        XCTAssertEqual(x, 94)
    }

    func testExpandedToggleNeverOverlapsTrafficLights() {
        let x = SidebarChromeMetrics.toggleOriginX(
            isSidebarCollapsed: false,
            expandedSidebarWidth: 132,
            toggleWidth: 70,
            trafficLightRightX: 104
        )

        XCTAssertEqual(x, 124)
    }
}
