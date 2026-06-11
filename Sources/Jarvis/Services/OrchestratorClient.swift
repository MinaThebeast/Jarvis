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
    let model: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, name, model, status
        case roleId = "role_id"
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

    func runAgent(agentId: Int, task: String, context: String? = nil) async throws -> String {
        var body: [String: Any] = ["task": task]
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["context"] = context
        }
        let data = try await post(path: "agents/\(agentId)/run", body: body)
        let payload = try decoder.decode(FleetAgentTaskResponse.self, from: data)
        return payload.output
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

    private func post(path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw OrchestratorError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
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
