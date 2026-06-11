import ApplicationServices
import Foundation

struct MouseClickTool: JarvisTool {
    let actionSafety: ActionSafety
    let auditLog: ActionAuditLog

    let name = "mouse_click"
    let description = "Moves the cursor and clicks at screen coordinates."

    let parametersJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "x": [
                "type": "number",
                "description": "Horizontal screen coordinate."
            ] as [String: Any],
            "y": [
                "type": "number",
                "description": "Vertical screen coordinate."
            ] as [String: Any],
            "button": [
                "type": "string",
                "enum": ["left", "right"],
                "description": "Mouse button to click. Defaults to left."
            ] as [String: Any],
            "double": [
                "type": "boolean",
                "description": "Whether to double-click. Defaults to false."
            ] as [String: Any]
        ],
        "required": ["x", "y"]
    ]

    func execute(arguments: [String: Any]) async throws -> String {
        guard let xValue = numericValue(from: arguments["x"]) else {
            let error = "Error: missing or invalid required parameter 'x'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }
        guard let yValue = numericValue(from: arguments["y"]) else {
            let error = "Error: missing or invalid required parameter 'y'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let buttonName = (arguments["button"] as? String ?? "left").lowercased()
        guard buttonName == "left" || buttonName == "right" else {
            let error = "Error: button must be 'left' or 'right'."
            auditLog.log(tool: name, arguments: arguments, error: error)
            return error
        }

        let isDouble = arguments["double"] as? Bool ?? false

        if let permissionError = AccessibilityCheck.requireTrusted() {
            auditLog.log(tool: name, arguments: arguments, error: permissionError)
            return permissionError
        }

        try actionSafety.checkAborted()

        let point = CGPoint(x: xValue, y: yValue)
        let mouseButton: CGMouseButton = buttonName == "right" ? .right : .left

        do {
            let result = try await Task.detached(priority: .userInitiated) { [actionSafety] in
                try Self.click(at: point, button: mouseButton, double: isDouble, actionSafety: actionSafety)
            }.value

            auditLog.log(tool: name, arguments: arguments, result: result)
            return result
        } catch {
            auditLog.log(tool: name, arguments: arguments, error: error.localizedDescription)
            throw error
        }
    }

    private static func click(
        at point: CGPoint,
        button: CGMouseButton,
        double: Bool,
        actionSafety: ActionSafety
    ) throws -> String {
        try actionSafety.checkAborted()

        guard let move = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: button
        ) else {
            throw InputControlError.eventCreationFailed
        }
        move.post(tap: .cghidEventTap)

        let clickCount = double ? 2 : 1
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp

        for index in 1...clickCount {
            try actionSafety.checkAborted()

            guard let down = CGEvent(
                mouseEventSource: nil,
                mouseType: downType,
                mouseCursorPosition: point,
                mouseButton: button
            ), let up = CGEvent(
                mouseEventSource: nil,
                mouseType: upType,
                mouseCursorPosition: point,
                mouseButton: button
            ) else {
                throw InputControlError.eventCreationFailed
            }

            down.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        let buttonLabel = button == .left ? "left" : "right"
        let clickKind = double ? "double \(buttonLabel) click" : "\(buttonLabel) click"
        return "Posted \(clickKind) at (\(Int(point.x)), \(Int(point.y))); effect not verified."
    }

    private func numericValue(from value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(number.doubleValue)
        case let double as Double:
            return CGFloat(double)
        case let int as Int:
            return CGFloat(int)
        default:
            return nil
        }
    }
}
