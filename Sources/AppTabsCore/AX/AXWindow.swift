import ApplicationServices
import CoreGraphics
import Foundation

/// Private-but-stable symbol mapping an AXUIElement to its CGWindowID.
/// Used by Rectangle, AltTab and other window utilities.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// A handle to another application's window, driven through the Accessibility API.
public struct AXWindow: Hashable {
    public let element: AXUIElement
    public let pid: pid_t

    public init(element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
    }

    public static func == (lhs: AXWindow, rhs: AXWindow) -> Bool {
        lhs.windowID == rhs.windowID && lhs.pid == rhs.pid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(pid)
    }

    // MARK: Identity

    /// The CGWindowID for this window, if resolvable.
    public var windowID: CGWindowID {
        var id: CGWindowID = 0
        let err = _AXUIElementGetWindow(element, &id)
        return err == .success ? id : 0
    }

    // MARK: Attributes

    public var title: String? {
        copyAttribute(kAXTitleAttribute as CFString) as? String
    }

    public var role: String? {
        copyAttribute(kAXRoleAttribute as CFString) as? String
    }

    public var subrole: String? {
        copyAttribute(kAXSubroleAttribute as CFString) as? String
    }

    public var isStandardWindow: Bool {
        (subrole ?? "") == kAXStandardWindowSubrole
    }

    public var isMinimized: Bool {
        (copyAttribute(kAXMinimizedAttribute as CFString) as? Bool) ?? false
    }

    public var isFullScreen: Bool {
        (copyAttribute("AXFullScreen" as CFString) as? Bool) ?? false
    }

    /// Frame in global screen coordinates (top-left origin, as AX reports).
    public var frame: CGRect {
        get {
            var position = CGPoint.zero
            var size = CGSize.zero
            if let posValue = copyAttribute(kAXPositionAttribute as CFString),
               CFGetTypeID(posValue) == AXValueGetTypeID(),
               AXValueGetType(unsafeBitCast(posValue, to: AXValue.self)) == .cgPoint {
                AXValueGetValue(unsafeBitCast(posValue, to: AXValue.self), .cgPoint, &position)
            }
            if let sizeValue = copyAttribute(kAXSizeAttribute as CFString),
               CFGetTypeID(sizeValue) == AXValueGetTypeID(),
               AXValueGetType(unsafeBitCast(sizeValue, to: AXValue.self)) == .cgSize {
                AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size)
            }
            return CGRect(origin: position, size: size)
        }
        set {
            set(position: newValue.origin)
            set(size: newValue.size)
        }
    }

    public func set(position: CGPoint) {
        var p = position
        if let value = AXValueCreate(.cgPoint, &p) {
            setAttribute(kAXPositionAttribute as CFString, value: value)
        }
    }

    public func set(size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) {
            setAttribute(kAXSizeAttribute as CFString, value: value)
        }
    }

    // MARK: Actions

    public func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    public func close() {
        if let btn = copyAttribute(kAXCloseButtonAttribute as CFString),
           CFGetTypeID(btn) == AXUIElementGetTypeID() {
            let closeButton = unsafeBitCast(btn, to: AXUIElement.self)
            AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        }
    }

    // MARK: Low-level

    private func copyAttribute(_ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, name, &value)
        guard err == .success else { return nil }
        return value
    }

    @discardableResult
    private func setAttribute(_ name: CFString, value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, name, value)
    }
}
