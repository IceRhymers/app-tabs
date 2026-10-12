import ApplicationServices
import CoreGraphics
import Foundation

/// Accessibility permission helpers.
public enum Permissions {
    /// Whether this process is trusted for Accessibility. Does not prompt.
    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility access. Returns current state.
    @MainActor
    @discardableResult
    public static func requestAccessibility(prompt: Bool = true) -> Bool {
        // Literal value of kAXTrustedCheckOptionPrompt ("AXTrustedCheckOptionPrompt").
        // Using the literal avoids referencing the non-Sendable global.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Poll until granted (or timeout), useful for onboarding flows.
    public static func waitForTrust(timeout: TimeInterval = 120, interval: TimeInterval = 0.5) async -> Bool {
        var elapsed: TimeInterval = 0
        while elapsed < timeout {
            if AXIsProcessTrusted() { return true }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            elapsed += interval
        }
        return AXIsProcessTrusted()
    }
}
