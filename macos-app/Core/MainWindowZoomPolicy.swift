import CoreGraphics

enum MainWindowZoomPolicy {
    /// Covers the native titlebar plus the unified toolbar band shown above the
    /// app's content. This matches the visible top strip users expect to double-click.
    static let minimumDoubleClickBandHeight: CGFloat = 96

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
