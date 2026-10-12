import CoreGraphics
import Foundation

/// Geometry helpers for positioning the tab strip relative to grouped windows.
/// All coordinates are in AppKit screen space (bottom-left origin) unless noted.
public enum FrameMath {
    public static let stripHeight: CGFloat = 28

    /// Frame for the tab strip given the active window's frame (AX coordinates: top-left origin)
    /// and the visible frame of the screen it's on (AppKit coordinates: bottom-left origin).
    ///
    /// Prefers to sit directly *above* the window's top edge when there's room;
    /// otherwise overlays the top of the window itself.
    @MainActor
    public static func stripFrame(
        forWindowFrame windowFrameAX: CGRect,
        screenVisibleFrame visible: CGRect,
        screenFrame full: CGRect
    ) -> CGRect {
        let windowFrame = axToAppKit(windowFrameAX, screenFrame: full)
        let aboveY = windowFrame.maxY
        let roomAbove = visible.maxY - aboveY
        let y: CGFloat = roomAbove >= stripHeight ? aboveY : windowFrame.maxY - stripHeight
        return CGRect(x: windowFrame.minX, y: y, width: windowFrame.width, height: stripHeight)
    }

    /// Convert AX (top-left origin, y down) to AppKit (bottom-left origin, y up) screen coordinates.
    @MainActor
    public static func axToAppKit(_ frame: CGRect, screenFrame: CGRect) -> CGRect {
        // AX y is measured from the top of the *primary* screen. AppKit y from bottom of primary screen.
        // For the primary screen (origin .zero in AppKit), conversion uses primary height.
        // We approximate using the passed screen's full frame height which is correct for the primary screen
        // and consistent for others in typical setups.
        let primaryHeight = NSScreenPrimaryHeightProvider.height
        let y = primaryHeight - frame.origin.y - frame.height
        return CGRect(x: frame.origin.x, y: y, width: frame.width, height: frame.height)
    }

    /// Convert AppKit to AX coordinates.
    @MainActor
    public static func appKitToAX(_ frame: CGRect) -> CGRect {
        let primaryHeight = NSScreenPrimaryHeightProvider.height
        let y = primaryHeight - frame.origin.y - frame.height
        return CGRect(x: frame.origin.x, y: y, width: frame.width, height: frame.height)
    }

    /// A rect far off-screen for parking inactive windows.
    public static let parkingSpot = CGRect(x: -10_000, y: -10_000, width: 800, height: 600)
}

/// Injected so AppTabsCore doesn't import AppKit. The app sets this at launch.
/// All access happens on the main thread (window management is main-thread by nature).
public enum NSScreenPrimaryHeightProvider {
    @MainActor public static var height: CGFloat = 1080
}
