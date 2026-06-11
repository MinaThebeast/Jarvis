import ApplicationServices
import Foundation

enum AccessibilityCheck {
    static let permissionError =
        "Enable Accessibility for JARVIS in System Settings > Privacy & Security > Accessibility."

    /// Returns `nil` when trusted; otherwise the user-facing permission error.
    static func requireTrusted(prompt: Bool = true) -> String? {
        isTrusted(prompt: prompt) ? nil : permissionError
    }

    static func isTrusted(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
