import Foundation

struct ShellTool: JarvisTool {
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog

    let name = "run_shell"
    let description = "Runs a shell command via zsh and returns combined stdout and stderr."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "command": [
                "type": "string",
                "description": "The shell command to run."
            ] as [String: Any]
        ],
        "required": ["command"]
    ]

    private static let outputLimit = 4000

    private static let destructivePatterns = [
        "rm -rf /",
        "rm -rf ~",
        "rm -rf *",
        "mkfs",
        "dd if=",
        "dd of=",
        "diskutil erase",
        "> /dev/",
        "shutdown",
        "reboot",
        "halt",
        ":(){",
        "killall",
        "sudo rm",
        "chmod -r 000"
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let command = arguments["command"] as? String else {
            let error = "Error: missing required parameter 'command'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let error = "Error: command cannot be empty."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        if !JarvisConfig.allowDestructiveShellCommands && Self.isDestructive(trimmed) {
            let refusal = "Refused: '\(trimmed)' looks destructive and destructive shell commands are disabled."
            auditLog.log(tool: name, arguments: arguments, error: refusal)
            return refusal
        }

        try actionSafety.checkAborted()

        let result = await Task.detached(priority: .userInitiated) { [actionSafety] in
            Self.runShell(trimmed, actionSafety: actionSafety)
        }.value

        auditLog.log(tool: name, arguments: arguments, result: result)
        return result
    }

    private static func isDestructive(_ command: String) -> Bool {
        let lower = command.lowercased()
        return destructivePatterns.contains { lower.contains($0) }
    }

    private static func runShell(_ command: String, actionSafety: ActionSafety) -> String {
        if actionSafety.abortRequested {
            return "Shell command aborted by kill-switch."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return "Error: failed to start shell command — \(error.localizedDescription)"
        }

        let timeout = JarvisConfig.shellTimeoutSeconds
        let start = Date()

        while process.isRunning {
            if actionSafety.abortRequested {
                process.terminate()
                process.waitUntilExit()
                return "Shell command aborted by kill-switch."
            }
            if Date().timeIntervalSince(start) > timeout {
                process.terminate()
                process.waitUntilExit()
                return "Shell command timed out after \(Int(timeout)) seconds."
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var combined = stdout
        if !stderr.isEmpty {
            if combined.isEmpty {
                combined = stderr
            } else if !combined.hasSuffix("\n") {
                combined += "\n" + stderr
            } else {
                combined += stderr
            }
        }

        if process.terminationStatus != 0 {
            let prefix = "Exit code \(process.terminationStatus)"
            combined = combined.isEmpty ? prefix : "\(prefix)\n\(combined)"
        }

        if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            combined = "Command completed with no output."
        }

        return truncateOutput(combined)
    }

    private static func truncateOutput(_ text: String) -> String {
        guard text.count > outputLimit else { return text }
        return String(text.prefix(outputLimit)) + "\n...[output truncated at \(outputLimit) characters]"
    }
}
