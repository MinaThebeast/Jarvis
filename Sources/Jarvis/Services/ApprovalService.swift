import Combine
import Foundation

struct PendingApproval: Identifiable, Equatable {
    let id: UUID
    let toolName: String
    let summary: String
    let riskClass: RiskClass

    init(toolName: String, summary: String, riskClass: RiskClass) {
        self.id = UUID()
        self.toolName = toolName
        self.summary = summary
        self.riskClass = riskClass
    }
}

@MainActor
final class ApprovalService: ObservableObject {
    @Published private(set) var pending: PendingApproval?

    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    func requestApproval(tool: String, summary: String, risk: RiskClass) async -> Bool {
        if pending != nil {
            resolve(approved: false)
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pending = PendingApproval(
                toolName: tool,
                summary: summary,
                riskClass: risk
            )

            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                let nanoseconds = UInt64(JarvisConfig.approvalTimeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                await MainActor.run {
                    self?.resolve(approved: false)
                }
            }
        }
    }

    func approve() {
        resolve(approved: true)
    }

    func deny() {
        resolve(approved: false)
    }

    private func resolve(approved: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pending = nil

        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: approved)
    }
}
