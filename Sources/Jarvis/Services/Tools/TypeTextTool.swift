import ApplicationServices
import Foundation

struct TypeTextTool: JarvisTool {
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog

    let name = "type_text"
    let description = "Types text into the frontmost application via simulated keyboard events."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "text": [
                "type": "string",
                "description": "The text to type into the active application."
            ] as [String: Any]
        ],
        "required": ["text"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let text = arguments["text"] as? String else {
            let error = "Error: missing required parameter 'text'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        guard !text.isEmpty else {
            let error = "Error: text cannot be empty."
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
                try Self.typeText(text, actionSafety: actionSafety)
            }.value

            auditLog.log(tool: name, arguments: arguments, result: result)
            return result
        } catch {
            auditLog.log(tool: name, arguments: arguments, error: error.localizedDescription)
            throw error
        }
    }

    private static func typeText(_ text: String, actionSafety: ActionSafety) throws -> String {
        try actionSafety.checkAborted()

        for character in text {
            try actionSafety.checkAborted()

            var uniChars = Array(String(character).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw InputControlError.eventCreationFailed
            }

            keyDown.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: &uniChars)
            keyUp.keyboardSetUnicodeString(stringLength: uniChars.count, unicodeString: &uniChars)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }

        return "Sent the text as keystrokes to the frontmost app. Keystrokes only register if an editable field had focus — this was not verified."
    }
}
