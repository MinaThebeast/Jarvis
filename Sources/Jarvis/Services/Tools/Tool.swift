import Foundation

// MARK: - Tool Protocol

protocol JarvisTool {
    var name: String { get }
    var description: String { get }
    var parametersJSONSchema: [String: Any] { get }
    func execute(arguments: [String: Any]) async throws -> String
}

// MARK: - Tool Registry

final class ToolRegistry {

    private var tools: [String: JarvisTool] = [:]

    init(_ tools: [JarvisTool] = []) {
        tools.forEach { register($0) }
    }

    func register(_ tool: JarvisTool) {
        tools[tool.name] = tool
    }

    func tool(named name: String) -> JarvisTool? {
        tools[name]
    }

    var isEmpty: Bool { tools.isEmpty }

    /// OpenAI `tools` array for chat completions requests.
    func openAIToolsArray() -> [[String: Any]] {
        tools.values.map { tool in
            [
                "type": "function",
                "function": [
                    "name":        tool.name,
                    "description": tool.description,
                    "parameters":  tool.parametersJSONSchema
                ] as [String: Any]
            ] as [String: Any]
        }
    }
}
