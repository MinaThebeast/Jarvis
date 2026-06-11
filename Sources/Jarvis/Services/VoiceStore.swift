import Foundation

struct VoicePreference: Codable, Equatable {
    var voice: String
}

final class VoiceStore: ObservableObject {

    @Published private(set) var voiceKey: String

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL = JarvisStorage.supportDirectory) {
        fileURL = directory.appendingPathComponent("voice.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let saved = try? decoder.decode(VoicePreference.self, from: data),
           JarvisConfig.ttsVoiceMapping[saved.voice] != nil {
            voiceKey = saved.voice
        } else {
            voiceKey = JarvisConfig.defaultTtsVoiceKey
        }
    }

    var openAIVoiceName: String {
        JarvisConfig.openAIVoice(for: voiceKey)
    }

    @discardableResult
    func setVoice(_ key: String) -> Bool {
        guard JarvisConfig.ttsVoiceMapping[key] != nil else { return false }
        voiceKey = key
        persist(key: key)
        return true
    }

    private func persist(key: String) {
        do {
            let data = try encoder.encode(VoicePreference(voice: key))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence failure should not interrupt voice switching.
        }
    }
}
