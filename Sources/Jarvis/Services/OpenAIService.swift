import Foundation

// MARK: - Chat Completion Result

struct ChatCompletionResult {
    let content: String?
    let toolCalls: [ToolCall]?

    var hasToolCalls: Bool {
        guard let toolCalls, !toolCalls.isEmpty else { return false }
        return true
    }
}

struct ToolCall: Equatable {
    let id: String
    let name: String
    let arguments: String
}

// MARK: - OpenAI Service

final class OpenAIService {

    private let voiceStore: VoiceStore

    init(voiceStore: VoiceStore) {
        self.voiceStore = voiceStore
    }

    // MARK: API Key resolution

    var apiKey: String {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.isEmpty {
            return env
        }
        return KeychainHelper.load(key: "openai_api_key") ?? ""
    }

    var hasKey: Bool { !apiKey.isEmpty }

    func saveAPIKey(_ key: String) {
        KeychainHelper.save(key, forKey: "openai_api_key")
    }

    func clearAPIKey() {
        KeychainHelper.delete(key: "openai_api_key")
    }

    // MARK: Chat Completion

    /// Sends a chat completion request. Pass the full messages array for agent loops.
    func chat(
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil
    ) async throws -> ChatCompletionResult {
        guard hasKey else { throw OpenAIError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        var body: [String: Any] = [
            "model":       JarvisConfig.chatModel,
            "messages":    messages,
            "max_tokens":  JarvisConfig.maxTokens,
            "temperature": 0.7
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let choice = decoded.choices.first else {
            throw OpenAIError.emptyResponse
        }

        let msg = choice.message
        let toolCalls = msg.toolCalls?.map {
            ToolCall(id: $0.id, name: $0.function.name, arguments: $0.function.arguments)
        }

        if msg.content == nil && (toolCalls == nil || toolCalls!.isEmpty) {
            throw OpenAIError.emptyResponse
        }

        return ChatCompletionResult(content: msg.content, toolCalls: toolCalls)
    }

    /// Convenience wrapper for a single user turn with conversation history.
    func chat(
        history: [Message],
        userText: String,
        tools: [[String: Any]]? = nil
    ) async throws -> ChatCompletionResult {
        var messages: [[String: Any]] = [
            ["role": "system", "content": JarvisConfig.systemPrompt]
        ]
        let context = history.suffix(JarvisConfig.maxContextMessages)
        messages += context.map { $0.openAIPayload }
        messages.append(["role": "user", "content": userText])
        return try await chat(messages: messages, tools: tools)
    }

    // MARK: Vision

    func vision(question: String, jpegBase64: String) async throws -> String {
        guard hasKey else { throw OpenAIError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        let content: [[String: Any]] = [
            ["type": "text", "text": question],
            [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(jpegBase64)"
                ] as [String: Any]
            ]
        ]

        let body: [String: Any] = [
            "model":      JarvisConfig.chatModel,
            "messages":   [["role": "user", "content": content]],
            "max_tokens": JarvisConfig.maxTokens
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)

        let decoded = try JSONDecoder().decode(VisionCompletionResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIError.emptyResponse
        }
        return text
    }

    /// Low-cost ambient screen summary for background perception.
    func ambientScreenSummary(jpegBase64: String) async throws -> String {
        guard hasKey else { throw OpenAIError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45

        let prompt = """
        Briefly summarize what is on screen in 1-2 sentences. \
        Focus on the active application and visible content. Be factual and concise.
        """

        let content: [[String: Any]] = [
            ["type": "text", "text": prompt],
            [
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(jpegBase64)",
                    "detail": "low"
                ] as [String: Any]
            ]
        ]

        let body: [String: Any] = [
            "model":      JarvisConfig.chatModel,
            "messages":   [["role": "user", "content": content]],
            "max_tokens": 120
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)

        let decoded = try JSONDecoder().decode(VisionCompletionResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Text-to-Speech

    func textToSpeech(_ text: String) async throws -> Data {
        guard hasKey else { throw OpenAIError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "model":           JarvisConfig.ttsModel,
            "input":           text,
            "voice":           voiceStore.openAIVoiceName,
            "response_format": "mp3",
            "speed":           1.05
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
        return data
    }

    // MARK: Whisper Transcription (fallback)

    func transcribe(audioData: Data, mimeType: String = "audio/m4a") async throws -> String {
        guard hasKey else { throw OpenAIError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let boundary = "JarvisBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendString(_ s: String) { body.append(s.data(using: .utf8)!) }

        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        appendString("\r\n--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n")
        appendString("--\(boundary)--\r\n")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response: response, data: data)
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return decoded.text
    }

    // MARK: Helpers

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("No HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? "HTTP \(http.statusCode)"
            throw OpenAIError.api(msg)
        }
    }
}

// MARK: - Decodable Models

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: AssistantMessage
    }
    let choices: [Choice]
}

private struct AssistantMessage: Decodable {
    let content: String?
    let toolCalls: [ToolCallResponse]?

    enum CodingKeys: String, CodingKey {
        case content
        case toolCalls = "tool_calls"
    }
}

private struct ToolCallResponse: Decodable {
    let id: String
    let type: String
    let function: FunctionPayload

    struct FunctionPayload: Decodable {
        let name: String
        let arguments: String
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct VisionCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Errors

enum OpenAIError: Error, LocalizedError {
    case noAPIKey
    case emptyResponse
    case api(String)
    case network(String)
    case toolNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:             return "No OpenAI API key configured."
        case .emptyResponse:        return "Received an empty response."
        case .api(let msg):         return "API error: \(msg)"
        case .network(let msg):     return "Network error: \(msg)"
        case .toolNotFound(let n):  return "Tool not found: \(n)"
        }
    }
}

// MARK: - Agent Loop Helpers

enum ChatMessageBuilder {

    static func assistantMessage(result: ChatCompletionResult) -> [String: Any] {
        var message: [String: Any] = ["role": "assistant"]

        if let content = result.content, !content.isEmpty {
            message["content"] = content
        } else {
            message["content"] = NSNull()
        }

        if let toolCalls = result.toolCalls, !toolCalls.isEmpty {
            message["tool_calls"] = toolCalls.map { call in
                [
                    "id":   call.id,
                    "type": "function",
                    "function": [
                        "name":      call.name,
                        "arguments": call.arguments
                    ] as [String: Any]
                ] as [String: Any]
            }
        }

        return message
    }

    static func toolResultMessage(toolCallId: String, content: String) -> [String: Any] {
        [
            "role":         "tool",
            "tool_call_id": toolCallId,
            "content":      content
        ]
    }

    static func parseArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }
}
