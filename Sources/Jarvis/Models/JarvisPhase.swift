import SwiftUI

// MARK: - App Phase State Machine

enum JarvisPhase: Equatable {
    case idle
    case wakeDetected
    case listening
    case processing
    case actingTool(String)
    case responding(String)
    case error(String)

    var label: String {
        switch self {
        case .idle:             return "STANDBY"
        case .wakeDetected:     return "INITIALIZING"
        case .listening:        return "LISTENING"
        case .processing:       return "PROCESSING"
        case .actingTool(let name):
            return name.hasPrefix("see_") ? "ANALYZING VISION" : "EXECUTING TOOL"
        case .responding:       return "RESPONDING"
        case .error:            return "SYSTEM ERROR"
        }
    }

    var subLabel: String {
        switch self {
        case .idle:             return "Say \"Hey JARVIS\" to begin"
        case .wakeDetected:     return "Yes, sir?"
        case .listening:        return "Speak your command..."
        case .processing:       return "Analyzing request..."
        case .actingTool(let name):
            return name.hasPrefix("see_") ? "Analyzing screen..." : "Running \(name)..."
        case .responding(let t): return t
        case .error(let msg):   return msg
        }
    }

    var accentColor: Color {
        switch self {
        case .idle:         return .jarvisBlue
        case .wakeDetected: return .jarvisCyan
        case .listening:    return .jarvisGreen
        case .processing:   return .jarvisGold
        case .actingTool:   return .jarvisGold
        case .responding:   return .jarvisCyan
        case .error:        return .jarvisRed
        }
    }

    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }

    var isListeningOrWake: Bool {
        switch self {
        case .listening, .wakeDetected: return true
        default: return false
        }
    }

    var isProcessing: Bool {
        switch self {
        case .processing, .actingTool: return true
        default: return false
        }
    }

    var isResponding: Bool {
        if case .responding = self { return true }
        return false
    }

    var ringSpeed: Double {
        switch self {
        case .idle:         return 8.0
        case .wakeDetected: return 3.0
        case .listening:    return 2.0
        case .processing:   return 1.5
        case .actingTool:   return 1.2
        case .responding:   return 2.5
        case .error:        return 6.0
        }
    }
}

// MARK: - JARVIS Color Palette

extension Color {
    static let jarvisBlue    = Color(red: 0.0,  green: 0.749, blue: 1.0)     // #00BFFF
    static let jarvisCyan    = Color(red: 0.0,  green: 1.0,   blue: 1.0)     // #00FFFF
    static let jarvisGreen   = Color(red: 0.0,  green: 0.9,   blue: 0.502)   // #00E680
    static let jarvisGold    = Color(red: 1.0,  green: 0.843, blue: 0.0)     // #FFD700
    static let jarvisRed     = Color(red: 1.0,  green: 0.2,   blue: 0.2)     // #FF3333
    static let jarvisDark    = Color(red: 0.0,  green: 0.027, blue: 0.055)   // #000711
    static let jarvisMid     = Color(red: 0.0,  green: 0.078, blue: 0.157)   // #001428
    static let jarvisPanel   = Color(red: 0.0,  green: 0.149, blue: 0.298)   // #002648

    static func jarvisGlow(_ phase: JarvisPhase) -> Color {
        phase.accentColor
    }
}
