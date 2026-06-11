import Foundation

enum LocalAgentError: LocalizedError {
    case notAttached
    case noGrantedTools

    var errorDescription: String? {
        switch self {
        case .notAttached:
            return "Local agent runner is not attached to the view model."
        case .noGrantedTools:
            return "Agent has no recognized local tools in granted_tools."
        }
    }
}

@MainActor
final class LocalAgentRunner {
    private weak var viewModel: JarvisViewModel?
    private var masterRegistry: ToolRegistry?

    func attach(viewModel: JarvisViewModel, masterRegistry: ToolRegistry) {
        self.viewModel = viewModel
        self.masterRegistry = masterRegistry
    }

    func run(agent: OrchestratorAgent, task: String, context: String?) async throws -> String {
        guard let viewModel, let masterRegistry else {
            throw LocalAgentError.notAttached
        }

        let scoped = masterRegistry.subset(named: agent.grantedTools)
        guard !scoped.isEmpty else {
            throw LocalAgentError.noGrantedTools
        }

        viewModel.activityCenter.post(.fleet, "Agent \(agent.name) acting locally…")

        var userText = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userText = "Context:\n\(context.trimmingCharacters(in: .whitespacesAndNewlines))\n\nTask:\n\(userText)"
        }

        var priorMessages: [[String: Any]] = []
        let hasSeeTool = agent.grantedTools.contains { name in
            name == "see_screen" || name == "see_active_window"
        }
        if hasSeeTool, let screenContext = viewModel.perceptionService.contextMessage {
            priorMessages.append([
                "role": "system",
                "content": screenContext
            ])
        }

        return try await viewModel.runToolLoop(
            systemPrompt: agent.systemPrompt,
            userText: userText,
            toolRegistry: scoped,
            priorMessages: priorMessages
        )
    }
}
