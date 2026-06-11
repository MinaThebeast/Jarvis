import Foundation

struct GetTimeTool: JarvisTool {
    let name = "get_time"
    let description = "Returns the current local date and time."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [String: Any](),
        "required": [String]()
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        formatter.locale = Locale.current
        return formatter.string(from: Date())
    }
}
