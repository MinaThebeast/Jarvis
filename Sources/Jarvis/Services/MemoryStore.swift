import Foundation

struct MemoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
    }
}

final class MemoryStore {

    private let fileURL: URL
    private var entries: [MemoryEntry]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL = JarvisStorage.supportDirectory) {
        fileURL = directory.appendingPathComponent("memory.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let loaded = try? decoder.decode([MemoryEntry].self, from: data) {
            entries = loaded.sorted { $0.createdAt < $1.createdAt }
        } else {
            entries = []
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append(MemoryEntry(text: trimmed))
        persist()
    }

    func all() -> [MemoryEntry] {
        entries
    }

    func search(_ query: String) -> [MemoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return entries }

        let keywords = trimmed
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        return entries.filter { entry in
            let haystack = entry.text.lowercased()
            return keywords.allSatisfy { haystack.contains($0) }
        }
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence failure should not interrupt tool execution.
        }
    }
}
