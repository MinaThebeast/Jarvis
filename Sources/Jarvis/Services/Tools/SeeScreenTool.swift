import Foundation

struct SeeScreenTool: JarvisTool {
    let openAI: OpenAIService
    let screenCapture: ScreenCaptureService

    let name = "see_screen"
    let description = "Captures the full screen and answers a question about what is visible."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "question": [
                "type": "string",
                "description": "What to look for or answer about the full screen."
            ] as [String: Any]
        ],
        "required": ["question"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let question = arguments["question"] as? String else {
            return "Error: missing required parameter 'question'."
        }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: question cannot be empty."
        }

        let jpeg = try screenCapture.captureFullScreen()
        let base64 = screenCapture.jpegBase64(from: jpeg)
        return try await openAI.vision(question: trimmed, jpegBase64: base64)
    }
}
