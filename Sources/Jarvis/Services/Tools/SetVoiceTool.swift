import Foundation

struct SetVoiceTool: JarvisTool {
    let voiceStore: VoiceStore

    let name = "set_voice"
    let description = "Switches JARVIS spoken voice between female and male for all future replies."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "voice": [
                "type": "string",
                "enum": ["female", "male"],
                "description": "The voice profile to use for text-to-speech."
            ] as [String: Any]
        ],
        "required": ["voice"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let voice = arguments["voice"] as? String else {
            return "Error: missing required parameter 'voice'."
        }

        let key = voice.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard voiceStore.setVoice(key) else {
            return "Error: voice must be 'female' or 'male'."
        }

        let openAIVoice = JarvisConfig.openAIVoice(for: key)
        return "Voice switched to \(key) (\(openAIVoice))."
    }
}
