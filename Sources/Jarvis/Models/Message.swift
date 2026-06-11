import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    init(role: Role, content: String) {
        self.id        = UUID()
        self.role      = role
        self.content   = content
        self.timestamp = Date()
    }

    var openAIPayload: [String: String] {
        ["role": role.rawValue, "content": content]
    }
}
