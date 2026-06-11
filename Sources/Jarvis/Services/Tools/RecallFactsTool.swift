import Foundation

struct RecallFactsTool: JarvisTool {
    let memoryStore: MemoryStore

    let name = "recall_facts"
    let description = "Retrieves stored facts, optionally filtered by a keyword query."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "Optional keyword query. If omitted or empty, returns all stored facts."
            ] as [String: Any]
        ],
        "required": [String]()
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        let query = arguments["query"] as? String ?? ""
        let matches = memoryStore.search(query)

        guard !matches.isEmpty else {
            return "No stored facts."
        }

        return matches.map(\.text).joined(separator: "\n")
    }
}
