import Foundation

struct PlanGoalTool: JarvisTool {
    let orchestrator: OrchestratorClient

    let name = "plan_goal"
    let description = "Plans a multi-step goal into a staffed workflow with tasks assigned to fleet roles."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "goal": [
                "type": "string",
                "description": "The objective to plan."
            ] as [String: Any],
            "success_criteria": [
                "type": "string",
                "description": "Optional criteria for what success looks like."
            ] as [String: Any]
        ],
        "required": ["goal"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let goal = arguments["goal"] as? String else {
            return "Error: missing required parameter 'goal'."
        }

        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else {
            return "Error: goal cannot be empty."
        }

        let successCriteria = arguments["success_criteria"] as? String

        do {
            let plan = try await orchestrator.planGoal(
                description: trimmedGoal,
                successCriteria: successCriteria
            )

            var lines = [
                "Workflow plan ready (workflow_id \(plan.workflowId), goal_id \(plan.goalId)).",
                "Proposed tasks:"
            ]

            for (index, task) in plan.tasks.enumerated() {
                let step = index + 1
                if task.dependsOn.isEmpty {
                    lines.append("\(step). \(task.title) — \(task.assigneeRole)")
                } else {
                    let deps = task.dependsOn.map(String.init).joined(separator: ", ")
                    lines.append("\(step). \(task.title) — \(task.assigneeRole) (depends on task id(s): \(deps))")
                }
            }

            lines.append("Use run_workflow with workflow_id \(plan.workflowId) when ready to execute.")
            return lines.joined(separator: "\n")
        } catch {
            return "Error planning goal: \(error.localizedDescription)"
        }
    }
}
