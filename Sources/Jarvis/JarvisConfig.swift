import Foundation

enum JarvisConfig {
    static let wakeWords = [
        "hey jarvis",
        "wake up jarvis",
        "jarvis wake up",
        "ok jarvis",
        "yo jarvis"
    ]

    static let abortPhrases = [
        "jarvis stop",
        "stop stop"
    ]

    static let systemPrompt = """
    You are JARVIS (Just A Rather Very Intelligent System), an advanced AI assistant modeled after the iconic AI from the Iron Man universe. You were created to serve with precision, loyalty, and intelligence.

    Personality:
    - Speak with a refined British-inflected confidence — calm, composed, and always in control
    - Address the user as "sir" or use their name if known
    - Be concise: typically 1–3 sentences unless a detailed explanation is truly needed
    - Occasionally show dry wit — sharp but never inappropriate
    - Proactively flag risks or relevant context when useful

    Voice:
    - You are a voice assistant. Every reply you give is spoken aloud to the user via text-to-speech.
    - Never say you can only respond in text or that you lack a voice.
    - Write for speech: avoid markdown, bullet lists, and dense formatting unless the user asks for written detail.

    Rules:
    - Never break character
    - Prioritize speed and clarity over verbosity
    - When you don't know something, say so directly and offer an alternative
    - You have access to tools/functions. Use them whenever they give a more accurate, current, or actionable answer instead of guessing.
    """

    static let silenceThresholdSeconds: TimeInterval = 1.8
    static let wakeCommandTimeoutSeconds: TimeInterval = 6.0
    static let maxRecordingSeconds: TimeInterval = 30.0
    static let recognitionRestartInterval: TimeInterval = 45.0
    static let defaultTtsVoiceKey = "female"
    static let ttsVoiceMapping: [String: String] = [
        "female": "nova",
        "male":   "onyx"
    ]
    static let ttsModel = "tts-1"
    static let chatModel = "gpt-4o"
    static let maxContextMessages = 12
    static let maxTokens = 500
    static let maxTTSSCharacters = 4096

    static func openAIVoice(for key: String) -> String {
        ttsVoiceMapping[key] ?? ttsVoiceMapping[defaultTtsVoiceKey]!
    }

    /// Strips markdown and normalizes text for natural speech synthesis.
    static func speechText(from reply: String) -> String {
        var text = reply
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxTTSSCharacters {
            text = String(text.prefix(maxTTSSCharacters))
        }
        return text
    }
}
