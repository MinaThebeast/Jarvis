import Foundation

struct SaveDeliverableTool: JarvisTool {
    let auditLog: ActionAuditLog
    let deliverableService: DeliverableService
    let activityCenter: ActivityCenter

    init(
        auditLog: ActionAuditLog,
        deliverableService: DeliverableService = .shared,
        activityCenter: ActivityCenter
    ) {
        self.auditLog = auditLog
        self.deliverableService = deliverableService
        self.activityCenter = activityCenter
    }

    let name = "save_deliverable"
    let description = "Saves a document deliverable to disk as md, txt, or pdf and optionally opens it in Finder."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "content": [
                "type": "string",
                "description": "The document content to save."
            ] as [String: Any],
            "format": [
                "type": "string",
                "enum": ["md", "txt", "pdf"],
                "description": "Output format. Defaults to pdf."
            ] as [String: Any],
            "filename": [
                "type": "string",
                "description": "Base filename without extension."
            ] as [String: Any],
            "open": [
                "type": "boolean",
                "description": "Whether to open and reveal the file in Finder. Defaults to true."
            ] as [String: Any]
        ],
        "required": ["content", "filename"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let content = arguments["content"] as? String else {
            let error = "Error: missing required parameter 'content'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }
        guard let filename = arguments["filename"] as? String else {
            let error = "Error: missing required parameter 'filename'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            let error = "Error: content cannot be empty."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let trimmedFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFilename.isEmpty else {
            let error = "Error: filename cannot be empty."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let format = (arguments["format"] as? String ?? "pdf").lowercased()
        let shouldOpen = arguments["open"] as? Bool ?? true

        do {
            let url = try deliverableService.save(
                content: content,
                format: format,
                filename: trimmedFilename
            )

            if shouldOpen {
                deliverableService.reveal(url)
            }

            await activityCenter.post(.deliverable, "Created \(url.lastPathComponent)")

            let result = "Saved deliverable to \(url.path)"
            auditLog.log(tool: name, arguments: arguments, result: result)
            return result
        } catch {
            let message = "Error saving deliverable: \(error.localizedDescription)"
            auditLog.log(tool: name, arguments: arguments, error: message)
            return message
        }
    }
}
