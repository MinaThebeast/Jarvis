import Foundation

struct RunWorkflowTool: JarvisTool {
    let orchestrator: OrchestratorClient
    let activityCenter: ActivityCenter

    init(orchestrator: OrchestratorClient, activityCenter: ActivityCenter) {
        self.orchestrator = orchestrator
        self.activityCenter = activityCenter
    }

    let name = "run_workflow"
    let description = "Executes a planned workflow and returns the synthesized final result."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "workflow_id": [
                "type": "number",
                "description": "The workflow id returned by plan_goal."
            ] as [String: Any]
        ],
        "required": ["workflow_id"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let workflowId = numericInt(from: arguments["workflow_id"]) else {
            return "Error: missing or invalid required parameter 'workflow_id'."
        }

        do {
            let result = try await orchestrator.runWorkflow(workflowId: workflowId)
            await activityCenter.post(.workflow, "Workflow complete")

            let contributors = result.taskOutputs.map { output in
                "\(output.role) (\(output.status))"
            }
            let uniqueContributors = Array(Set(contributors)).sorted().joined(separator: ", ")

            var response = "Workflow \(workflowId) finished with status \(result.status)."
            if !uniqueContributors.isEmpty {
                response += " Contributors: \(uniqueContributors)."
            }
            response += "\n\nFinal result:\n\(result.finalResult)"
            return response
        } catch {
            return "Error running workflow: \(error.localizedDescription)"
        }
    }

    private func numericInt(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        default:
            return nil
        }
    }
}
