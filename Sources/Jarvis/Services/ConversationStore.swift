import Foundation

final class ConversationStore {

    private let fileURL: URL
    private let maxMessages = 200
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL = JarvisStorage.supportDirectory) {
        fileURL = directory.appendingPathComponent("conversation.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [Message] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([Message].self, from: data)
        } catch {
            return []
        }
    }

    func save(_ messages: [Message]) {
        let bounded = Array(messages.suffix(maxMessages))
        do {
            let data = try encoder.encode(bounded)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence failure should not interrupt conversation flow.
        }
    }
}
