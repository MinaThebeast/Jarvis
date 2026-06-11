import Foundation

struct RememberFactTool: JarvisTool {
    let memoryStore: MemoryStore

    let name = "remember_fact"
    let description = "Stores a durable fact about the user or ongoing context for future conversations."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "fact": [
                "type": "string",
                "description": "The fact to remember."
            ] as [String: Any]
        ],
        "required": ["fact"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let fact = arguments["fact"] as? String else {
            return "Error: missing required parameter 'fact'."
        }

        let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: fact cannot be empty."
        }

        memoryStore.add(trimmed)
        return "Fact remembered: \(trimmed)"
    }
}
