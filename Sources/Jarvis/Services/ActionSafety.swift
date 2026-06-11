import Foundation

enum ActionError: LocalizedError {
    case aborted

    var errorDescription: String? {
        "Action aborted by kill-switch."
    }
}

/// Thread-safe kill-switch shared by action tools and the view model.
final class ActionSafety {
    private let lock = NSLock()
    private var _abortRequested = false

    var abortRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _abortRequested
    }

    func requestAbort() {
        lock.lock()
        _abortRequested = true
        lock.unlock()
    }

    func resetAbort() {
        lock.lock()
        _abortRequested = false
        lock.unlock()
    }

    func checkAborted() throws {
        if abortRequested {
            throw ActionError.aborted
        }
    }
}
