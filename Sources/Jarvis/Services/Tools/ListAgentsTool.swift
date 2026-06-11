import Foundation

struct ListAgentsTool: JarvisTool {
    let orchestrator: OrchestratorClient

    let name = "list_agents"
    let description = "Lists the current roster of hired fleet agents."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [:] as [String: Any]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        do {
            let agents = try await orchestrator.listAgents()
            guard !agents.isEmpty else {
                return "No agents hired yet."
            }

            let roles = try await orchestrator.listRoles()
            let roleTitles = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0.title) })

            let lines = agents.map { agent in
                let roleTitle = roleTitles[agent.roleId] ?? "role \(agent.roleId)"
                return "- \(agent.name) (id \(agent.id), \(roleTitle), \(agent.status))"
            }
            return "Current agent roster:\n" + lines.joined(separator: "\n")
        } catch {
            return "Error listing agents: \(error.localizedDescription)"
        }
    }
}
