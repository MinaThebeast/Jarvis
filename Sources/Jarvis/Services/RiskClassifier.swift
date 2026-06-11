import Foundation

enum RiskClass: String {
    case digitalInternal
    case destructive
    case externalSend
    case money
    case publish
    case legal

    var requiresApproval: Bool {
        self != .digitalInternal
    }

    var label: String {
        switch self {
        case .digitalInternal: return "Internal"
        case .destructive:       return "Destructive"
        case .externalSend:      return "External Send"
        case .money:             return "Financial"
        case .publish:           return "Publish"
        case .legal:             return "Legal"
        }
    }
}

enum RiskClassifier {
    static func classify(tool: String, arguments: [String: Any]) -> RiskClass {
        let payload = combinedPayload(tool: tool, arguments: arguments)
        let lower = payload.lowercased()

        if tool == "run_shell" {
            if JarvisConfig.shellDestructivePatterns.contains(where: { lower.contains($0.lowercased()) }) {
                return .destructive
            }
        }

        guard tool == "run_shell" || tool == "run_applescript" else {
            return .digitalInternal
        }

        if JarvisConfig.riskMoneyKeywords.contains(where: { lower.contains($0) }) {
            return .money
        }
        if JarvisConfig.riskLegalKeywords.contains(where: { lower.contains($0) }) {
            return .legal
        }
        if JarvisConfig.riskPublishKeywords.contains(where: { lower.contains($0) }) {
            return .publish
        }
        if JarvisConfig.riskExternalSendKeywords.contains(where: { lower.contains($0) }) {
            return .externalSend
        }

        return .digitalInternal
    }

    static func summary(tool: String, arguments: [String: Any]) -> String {
        switch tool {
        case "run_shell":
            let command = (arguments["command"] as? String) ?? "unknown command"
            return "Run shell command: \(truncate(command, limit: 120))"
        case "run_applescript":
            let script = (arguments["script"] as? String) ?? "unknown script"
            return "Run AppleScript: \(truncate(script, limit: 120))"
        default:
            return tool.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func combinedPayload(tool: String, arguments: [String: Any]) -> String {
        switch tool {
        case "run_shell":
            return arguments["command"] as? String ?? ""
        case "run_applescript":
            return arguments["script"] as? String ?? ""
        default:
            return arguments.values.compactMap { value in
                if let string = value as? String { return string }
                return nil
            }.joined(separator: " ")
        }
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
