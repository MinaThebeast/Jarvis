import Foundation

enum OrchestratorError: LocalizedError {
    case invalidURL
    case badStatus(Int, String?)
    case invalidResponse
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid orchestrator URL."
        case .badStatus(let code, let detail):
            if let detail, !detail.isEmpty {
                return "Orchestrator returned HTTP \(code): \(detail)"
            }
            return "Orchestrator returned HTTP \(code)."
        case .invalidResponse:
            return "Invalid orchestrator response."
        case .notFound(let message):
            return message
        }
    }
}

struct OrchestratorRole: Decodable {
    let id: Int
    let title: String
    let responsibilities: String
}

struct OrchestratorAgent: Decodable {
    let id: Int
    let name: String
    let roleId: Int
    let systemPrompt: String
    let model: String
    let grantedTools: [String]
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, name, model, status
        case roleId = "role_id"
        case systemPrompt = "system_prompt"
        case grantedTools = "granted_tools"
    }

    var hasOSTools: Bool {
        !Set(grantedTools).isDisjoint(with: JarvisConfig.osToolNames)
    }
}

struct PlannedTask: Decodable {
    let id: Int
    let title: String
    let assigneeRole: String
    let status: String
    let dependsOn: [Int]

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case assigneeRole = "assignee_role"
        case dependsOn = "depends_on"
    }
}

struct GoalPlan: Decodable {
    let goalId: Int
    let workflowId: Int
    let tasks: [PlannedTask]

    enum CodingKeys: String, CodingKey {
        case tasks
        case goalId = "goal_id"
        case workflowId = "workflow_id"
    }
}

struct WorkflowTaskOutput: Decodable {
    let taskId: Int
    let title: String
    let role: String
    let status: String
    let output: String

    enum CodingKeys: String, CodingKey {
        case title, role, status, output
        case taskId = "task_id"
    }
}

struct WorkflowRunResult: Decodable {
    let goalId: Int
    let status: String
    let taskOutputs: [WorkflowTaskOutput]
    let finalResult: String

    enum CodingKeys: String, CodingKey {
        case status
        case goalId = "goal_id"
        case taskOutputs = "task_outputs"
        case finalResult = "final_result"
    }
}

struct OrchestratorSpendSummary: Decodable {
    let hourlyUsed: Int
    let hourlyCap: Int
    let dailyUsed: Int
    let dailyCap: Int

    enum CodingKeys: String, CodingKey {
        case hourlyUsed = "hourly_used"
        case hourlyCap = "hourly_cap"
        case dailyUsed = "daily_used"
        case dailyCap = "daily_cap"
    }

    var hudLabel: String {
        let used = formatTokens(hourlyUsed)
        let cap = hourlyCap > 0 ? formatTokens(hourlyCap) : "∞"
        return "\(used) / \(cap)"
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.0fk", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

struct AutonomyStatus: Decodable {
    let enabled: Bool
}

struct AutonomyEvent: Decodable, Identifiable {
    let id: Int
    let type: String
    let goalId: Int?
    let message: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, message
        case goalId = "goal_id"
        case createdAt = "created_at"
    }

    var isHighSignal: Bool {
        switch type {
        case "goal_completed", "goal_failed", "approval_needed", "spend_cap_skip":
            return true
        default:
            return type.contains("approval")
        }
    }

    var spokenLine: String {
        switch type {
        case "goal_completed":
            return "Sir, a fleet goal has completed."
        case "goal_failed":
            return "Sir, a fleet goal is blocked."
        case "approval_needed":
            return "Sir, fleet autonomy requires your approval."
        case "spend_cap_skip":
            return "Sir, fleet autonomy paused. Spend cap reached."
        default:
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > 160 {
                return String(trimmed.prefix(157)) + "..."
            }
            return trimmed
        }
    }
}

struct OrchestratorGoal: Decodable, Identifiable {
    let id: Int
    let description: String
    let successCriteria: String?
    let status: String
    let createdAt: String
    let workflowId: Int?

    enum CodingKeys: String, CodingKey {
        case id, description, status
        case successCriteria = "success_criteria"
        case createdAt = "created_at"
        case workflowId = "workflow_id"
    }

    var shortDescription: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 42 {
            return trimmed
        }
        return String(trimmed.prefix(39)) + "..."
    }
}

final class OrchestratorClient {
    let baseURL: URL
    private let decoder = JSONDecoder()

    init(baseURL: URL = URL(string: "http://127.0.0.1:8765")!) {
        self.baseURL = baseURL
    }

    func health() async -> Bool {
        guard let url = URL(string: "health", relativeTo: baseURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let payload = try decoder.decode(HealthResponse.self, from: data)
            return payload.status == "online"
        } catch {
            return false
        }
    }

    func listRoles() async throws -> [OrchestratorRole] {
        let data = try await get(path: "roles")
        return try decoder.decode([OrchestratorRole].self, from: data)
    }

    func hireAgent(name: String, roleId: Int) async throws -> OrchestratorAgent {
        let body: [String: Any] = [
            "name": name,
            "role_id": roleId
        ]
        let data = try await post(path: "agents", body: body)
        return try decoder.decode(OrchestratorAgent.self, from: data)
    }

    func listAgents() async throws -> [OrchestratorAgent] {
        let data = try await get(path: "agents")
        return try decoder.decode([OrchestratorAgent].self, from: data)
    }

    func getAgent(id: Int) async throws -> OrchestratorAgent {
        let data = try await get(path: "agents/\(id)")
        return try decoder.decode(OrchestratorAgent.self, from: data)
    }

    func runAgent(agentId: Int, task: String, context: String? = nil) async throws -> String {
        var body: [String: Any] = ["task": task]
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["context"] = context
        }
        let data = try await post(path: "agents/\(agentId)/run", body: body)
        let payload = try decoder.decode(FleetAgentTaskResponse.self, from: data)
        return payload.output
    }

    func planGoal(description: String, successCriteria: String? = nil) async throws -> GoalPlan {
        var body: [String: Any] = ["description": description]
        if let successCriteria, !successCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["success_criteria"] = successCriteria
        }
        let data = try await post(path: "goals/plan", body: body, timeout: 120)
        return try decoder.decode(GoalPlan.self, from: data)
    }

    func runWorkflow(workflowId: Int) async throws -> WorkflowRunResult {
        let data = try await post(path: "workflows/\(workflowId)/run", body: [:], timeout: 300)
        return try decoder.decode(WorkflowRunResult.self, from: data)
    }

    func halt() async throws {
        _ = try await post(path: "halt", body: [:], timeout: 10)
    }

    func resume() async throws {
        _ = try await post(path: "resume", body: [:], timeout: 10)
    }

    func getSpend() async throws -> OrchestratorSpendSummary {
        let data = try await get(path: "spend")
        return try decoder.decode(OrchestratorSpendSummary.self, from: data)
    }

    func getAutonomy() async throws -> AutonomyStatus {
        let data = try await get(path: "autonomy")
        return try decoder.decode(AutonomyStatus.self, from: data)
    }

    func setAutonomy(enabled: Bool) async throws -> AutonomyStatus {
        let data = try await post(path: "autonomy", body: ["enabled": enabled], timeout: 10)
        return try decoder.decode(AutonomyStatus.self, from: data)
    }

    func autonomyEvents(since: Int = 0) async throws -> [AutonomyEvent] {
        let data = try await get(path: "autonomy/events?since=\(since)")
        return try decoder.decode([AutonomyEvent].self, from: data)
    }

    func listGoals() async throws -> [OrchestratorGoal] {
        let data = try await get(path: "goals")
        return try decoder.decode([OrchestratorGoal].self, from: data)
    }

    func runAgent(
        systemPrompt: String,
        history: [Message],
        userText: String
    ) async throws -> String {
        let historyPayload = history.map {
            ["role": $0.role.rawValue, "content": $0.content]
        }
        let body: [String: Any] = [
            "system_prompt": systemPrompt,
            "history": historyPayload,
            "user_text": userText
        ]
        let data = try await post(path: "agent/run", body: body)
        let payload = try decoder.decode(LegacyAgentRunResponse.self, from: data)
        return payload.content
    }

    // MARK: - HTTP

    private func get(path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw OrchestratorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        return try await perform(request)
    }

    private func post(path: String, body: [String: Any], timeout: TimeInterval = 120) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw OrchestratorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OrchestratorError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = Self.errorDetail(from: data)
            throw OrchestratorError.badStatus(http.statusCode, detail)
        }
        return data
    }

    private static func errorDetail(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let detail = json["detail"] as? String {
            return detail
        }
        return nil
    }
}

private struct HealthResponse: Decodable {
    let status: String
}

private struct LegacyAgentRunResponse: Decodable {
    let content: String
}

private struct FleetAgentTaskResponse: Decodable {
    let agent: String
    let output: String
}
