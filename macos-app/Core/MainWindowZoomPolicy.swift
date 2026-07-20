import CoreGraphics

enum MainWindowZoomPolicy {
    /// Covers the native titlebar plus the unified toolbar band shown above the
    /// app's content. This matches the visible top strip users expect to double-click.
    static let minimumDoubleClickBandHeight: CGFloat = 96

    /// Expands across the screen while preserving only the menu-bar inset.
    /// `visibleFrame.minY` can reserve a hidden or always-visible Dock, which is
    /// why native window zoom may leave a large strip below the app.
    static func maximizedFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let topEdge = min(screenFrame.maxY, max(screenFrame.minY, visibleFrame.maxY))
        return CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: topEdge - screenFrame.minY
        )
    }

    static func framesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    static func isInDoubleClickZoomBand(
        clickY: CGFloat,
        contentHeight: CGFloat,
        nativeTitlebarHeight: CGFloat
    ) -> Bool {
        guard contentHeight > 0, clickY >= 0 else { return false }

        let bandHeight = min(
            contentHeight,
            max(nativeTitlebarHeight, minimumDoubleClickBandHeight)
        )
        return clickY >= contentHeight - bandHeight
    }
}
