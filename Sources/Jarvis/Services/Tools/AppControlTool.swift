import AppKit
import Foundation

struct AppControlTool: JarvisTool {
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog

    let name = "control_app"
    let description = "Opens, activates, or quits a macOS application by name."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": [
                "type": "string",
                "enum": ["open", "quit", "activate"],
                "description": "The action to perform on the application."
            ] as [String: Any],
            "app_name": [
                "type": "string",
                "description": "The application name, e.g. Safari or Notes."
            ] as [String: Any]
        ],
        "required": ["action", "app_name"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            let error = "Error: missing required parameter 'action'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }
        guard let appName = arguments["app_name"] as? String else {
            let error = "Error: missing required parameter 'app_name'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            let error = "Error: app_name cannot be empty."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        try actionSafety.checkAborted()

        do {
            let result = try await Task.detached(priority: .userInitiated) { [actionSafety] in
                try actionSafety.checkAborted()
                return try Self.perform(action: action, appName: trimmedName, actionSafety: actionSafety)
            }.value

            auditLog.log(tool: name, arguments: arguments, result: result)
            return result
        } catch {
            auditLog.log(tool: name, arguments: arguments, error: error.localizedDescription)
            throw error
        }
    }

    private static func perform(action: String, appName: String, actionSafety: ActionSafety) throws -> String {
        switch action.lowercased() {
        case "open":
            try actionSafety.checkAborted()
            try launchApplication(named: appName)
            return "Opened \(appName)."

        case "activate":
            try actionSafety.checkAborted()
            guard let app = findRunningApplication(named: appName) else {
                throw ActionControlError.appNotRunning(appName)
            }
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return "Activated \(appName)."

        case "quit":
            try actionSafety.checkAborted()
            if let app = findRunningApplication(named: appName) {
                app.terminate()
                return "Quit requested for \(appName)."
            }
            try quitViaAppleScript(appName: appName)
            return "Quit requested for \(appName)."

        default:
            throw ActionControlError.invalidAction(action)
        }
    }

    private static func launchApplication(named appName: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ActionControlError.launchFailed(appName)
        }
    }

    private static func findRunningApplication(named appName: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            matches(app: app, name: appName)
        }
    }

    private static func matches(app: NSRunningApplication, name: String) -> Bool {
        if let localized = app.localizedName,
           localized.localizedCaseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        if let bundleName = app.bundleURL?.deletingPathExtension().lastPathComponent,
           bundleName.localizedCaseInsensitiveCompare(name) == .orderedSame {
            return true
        }
        return false
    }

    private static func quitViaAppleScript(appName: String) throws {
        let escaped = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"\(escaped)\" to quit"
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw ActionControlError.appleScriptFailed(errorInfo.description)
        }
    }
}

enum ActionControlError: LocalizedError {
    case invalidAction(String)
    case appNotRunning(String)
    case launchFailed(String)
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAction(let action):
            return "Invalid action '\(action)'. Use open, quit, or activate."
        case .appNotRunning(let name):
            return "\(name) is not running."
        case .launchFailed(let name):
            return "Failed to open \(name)."
        case .appleScriptFailed(let detail):
            return "AppleScript failed: \(detail)"
        }
    }
}
