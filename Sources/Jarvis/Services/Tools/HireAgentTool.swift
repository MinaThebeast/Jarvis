import Foundation

struct HireAgentTool: JarvisTool {
    let orchestrator: OrchestratorClient

    let name = "hire_agent"
    let description = "Hires a specialist agent from the orchestrator fleet for a given role title."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": [
                "type": "string",
                "description": "The name for the new agent."
            ] as [String: Any],
            "role": [
                "type": "string",
                "description": "The role title to hire, e.g. Copywriter, Planner, or Analyst."
            ] as [String: Any]
        ],
        "required": ["name", "role"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let name = arguments["name"] as? String else {
            return "Error: missing required parameter 'name'."
        }
        guard let roleTitle = arguments["role"] as? String else {
            return "Error: missing required parameter 'role'."
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRole = roleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Error: name cannot be empty."
        }
        guard !trimmedRole.isEmpty else {
            return "Error: role cannot be empty."
        }

        do {
            let roles = try await orchestrator.listRoles()
            guard let role = roles.first(where: {
                $0.title.localizedCaseInsensitiveCompare(trimmedRole) == .orderedSame
            }) else {
                let available = roles.map(\.title).joined(separator: ", ")
                return "Error: role '\(trimmedRole)' not found. Available roles: \(available)."
            }

            let agent = try await orchestrator.hireAgent(name: trimmedName, roleId: role.id)
            return "Hired agent \(agent.name) (id \(agent.id)) for role \(role.title)."
        } catch {
            return "Error hiring agent: \(error.localizedDescription)"
        }
    }
}
