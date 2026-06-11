import ApplicationServices
import Foundation

struct PressKeysTool: JarvisTool {
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog

    let name = "press_keys"
    let description = "Presses a keyboard shortcut or key combination in the frontmost application."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "combo": [
                "type": "string",
                "description": "Key combination, e.g. cmd+c, cmd+shift+s, return, escape, tab."
            ] as [String: Any]
        ],
        "required": ["combo"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let combo = arguments["combo"] as? String else {
            let error = "Error: missing required parameter 'combo'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let trimmed = combo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let error = "Error: combo cannot be empty."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        if let permissionError = AccessibilityCheck.requireTrusted() {
            auditLog.log(tool: name, arguments: arguments, error: permissionError)
            return permissionError
        }

        try actionSafety.checkAborted()

        do {
            let result = try await Task.detached(priority: .userInitiated) { [actionSafety] in
                try Self.pressCombo(trimmed, actionSafety: actionSafety)
            }.value

            auditLog.log(tool: name, arguments: arguments, result: result)
            return result
        } catch {
            auditLog.log(tool: name, arguments: arguments, error: error.localizedDescription)
            throw error
        }
    }

    private static func pressCombo(_ combo: String, actionSafety: ActionSafety) throws -> String {
        try actionSafety.checkAborted()

        let parts = combo.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let keyPart = parts.last else {
            throw InputControlError.unknownKey(combo)
        }

        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            guard let flag = modifierFlags[modifier] else {
                throw InputControlError.unknownModifier(modifier)
            }
            flags.insert(flag)
        }

        guard let keyCode = keyCode(for: keyPart) else {
            throw InputControlError.unknownKey(keyPart)
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw InputControlError.eventCreationFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return "Posted \(combo); effect not verified."
    }

    private static let modifierFlags: [String: CGEventFlags] = [
        "cmd": .maskCommand,
        "command": .maskCommand,
        "shift": .maskShift,
        "option": .maskAlternate,
        "opt": .maskAlternate,
        "alt": .maskAlternate,
        "ctrl": .maskControl,
        "control": .maskControl
    ]

    private static let specialKeyCodes: [String: CGKeyCode] = [
        "return": 36,
        "enter": 36,
        "tab": 48,
        "space": 49,
        "delete": 51,
        "backspace": 51,
        "del": 51,
        "escape": 53,
        "esc": 53,
        "left": 123,
        "right": 124,
        "down": 125,
        "up": 126
    ]

    private static let letterKeyCodes: [Character: CGKeyCode] = [
        "a": 0,  "b": 11, "c": 8,  "d": 2,  "e": 14, "f": 3,  "g": 5,
        "h": 4,  "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1,  "t": 17, "u": 32,
        "v": 9,  "w": 13, "x": 7,  "y": 16, "z": 6
    ]

    private static let digitKeyCodes: [Character: CGKeyCode] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25
    ]

    private static func keyCode(for key: String) -> CGKeyCode? {
        if let code = specialKeyCodes[key] {
            return code
        }
        guard key.count == 1, let character = key.first else {
            return nil
        }
        if character.isLetter {
            return letterKeyCodes[character]
        }
        if character.isNumber {
            return digitKeyCodes[character]
        }
        return nil
    }
}

enum InputControlError: LocalizedError {
    case eventCreationFailed
    case unknownKey(String)
    case unknownModifier(String)

    var errorDescription: String? {
        switch self {
        case .eventCreationFailed:
            return "Failed to create keyboard event."
        case .unknownKey(let key):
            return "Unknown key '\(key)'."
        case .unknownModifier(let modifier):
            return "Unknown modifier '\(modifier)'."
        }
    }
}
