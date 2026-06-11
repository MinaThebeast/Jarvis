import Foundation

final class ActionAuditLog {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.jarvis.action-audit")
    private let formatter: ISO8601DateFormatter

    init(directory: URL = JarvisStorage.supportDirectory) {
        fileURL = directory.appendingPathComponent("actions.log")
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func log(tool: String, arguments: [String: Any], result: String) {
        append(tool: tool, arguments: arguments, outcome: result)
    }

    func log(tool: String, arguments: [String: Any], error: String) {
        append(tool: tool, arguments: arguments, outcome: error)
    }

    private func append(tool: String, arguments: [String: Any], outcome: String) {
        let timestamp = formatter.string(from: Date())
        let argsText = Self.serializeArguments(arguments)
        let sanitizedOutcome = outcome.replacingOccurrences(of: "\n", with: "\\n")
        let line = "\(timestamp) | \(tool) | \(argsText) | \(sanitizedOutcome)\n"

        queue.async { [fileURL] in
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    if let data = line.data(using: .utf8) {
                        handle.write(data)
                    }
                    try? handle.close()
                }
            } else {
                try? line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func serializeArguments(_ arguments: [String: Any]) -> String {
        if JSONSerialization.isValidJSONObject(arguments),
           let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: arguments)
    }
}
