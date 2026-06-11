import Foundation

struct DelegateTaskTool: JarvisTool {
    let orchestrator: OrchestratorClient
    let activityCenter: ActivityCenter
    let localAgentRunner: LocalAgentRunner

    init(
        orchestrator: OrchestratorClient,
        activityCenter: ActivityCenter,
        localAgentRunner: LocalAgentRunner
    ) {
        self.orchestrator = orchestrator
        self.activityCenter = activityCenter
        self.localAgentRunner = localAgentRunner
    }

    let name = "delegate_task"
    let description = "Delegates a task to a hired fleet agent and returns the agent's output."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "agent": [
                "type": "string",
                "description": "The agent name or numeric id."
            ] as [String: Any],
            "task": [
                "type": "string",
                "description": "The task for the agent to complete."
            ] as [String: Any],
            "context": [
                "type": "string",
                "description": "Optional background context for the task."
            ] as [String: Any]
        ],
        "required": ["agent", "task"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let agentRef = arguments["agent"] as? String else {
            return "Error: missing required parameter 'agent'."
        }
        guard let task = arguments["task"] as? String else {
            return "Error: missing required parameter 'task'."
        }

        let trimmedRef = agentRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRef.isEmpty else {
            return "Error: agent cannot be empty."
        }
        guard !trimmedTask.isEmpty else {
            return "Error: task cannot be empty."
        }

        let context = arguments["context"] as? String

        do {
            let agents = try await orchestrator.listAgents()
            guard let summary = resolveAgent(ref: trimmedRef, from: agents) else {
                let roster = agents.map { "\($0.name) (id \($0.id))" }.joined(separator: ", ")
                if roster.isEmpty {
                    return "Error: agent '\(trimmedRef)' not found. No agents are hired yet."
                }
                return "Error: agent '\(trimmedRef)' not found. Current roster: \(roster)."
            }

            let agent = try await orchestrator.getAgent(id: summary.id)
            let output: String

            if agent.hasOSTools {
                output = try await localAgentRunner.run(
                    agent: agent,
                    task: trimmedTask,
                    context: context
                )
                await MainActor.run {
                    activityCenter.post(.fleet, "Delegated locally to \(agent.name)")
                }
            } else {
                output = try await orchestrator.runAgent(
                    agentId: agent.id,
                    task: trimmedTask,
                    context: context
                )
                await MainActor.run {
                    activityCenter.post(.fleet, "Delegated to \(agent.name)")
                }
            }

            return "Output from \(agent.name) (id \(agent.id)):\n\(output)"
        } catch {
            return "Error delegating task: \(error.localizedDescription)"
        }
    }

    private func resolveAgent(ref: String, from agents: [OrchestratorAgent]) -> OrchestratorAgent? {
        if let id = Int(ref) {
            return agents.first { $0.id == id }
        }
        return agents.first {
            $0.name.localizedCaseInsensitiveCompare(ref) == .orderedSame
        }
    }
}
