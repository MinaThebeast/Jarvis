import AppKit
import Foundation

struct AppleScriptTool: JarvisTool {
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog

    let name = "run_applescript"
    let description = "Executes an AppleScript snippet and returns its result."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "script": [
                "type": "string",
                "description": "The AppleScript source code to execute."
            ] as [String: Any]
        ],
        "required": ["script"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let script = arguments["script"] as? String else {
            let error = "Error: missing required parameter 'script'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let error = "Error: script cannot be empty."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        try actionSafety.checkAborted()

        do {
            let result = try await Task.detached(priority: .userInitiated) { [actionSafety] in
                try actionSafety.checkAborted()
                return try Self.runAppleScript(trimmed, actionSafety: actionSafety)
            }.value

            auditLog.log(tool: name, arguments: arguments, result: result)
            return result
        } catch {
            auditLog.log(tool: name, arguments: arguments, error: error.localizedDescription)
            throw error
        }
    }

    private static func runAppleScript(_ source: String, actionSafety: ActionSafety) throws -> String {
        try actionSafety.checkAborted()

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw ActionControlError.appleScriptFailed("Invalid AppleScript source.")
        }

        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw ActionControlError.appleScriptFailed(errorInfo.description)
        }

        if let stringValue = descriptor.stringValue, !stringValue.isEmpty {
            return stringValue
        }
        return "AppleScript executed successfully."
    }
}
