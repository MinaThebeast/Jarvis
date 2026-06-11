import Combine
import CoreGraphics
import Foundation

@MainActor
final class PerceptionService: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var latestSummary: String?
    @Published private(set) var latestSummaryAt: Date?

    private let screenCapture: ScreenCaptureService
    private let openAI: OpenAIService

    private var timer: Timer?
    private var lastFingerprint: UInt64?
    private var lastVisionCall: Date?
    private var isProcessingTick = false

    init(screenCapture: ScreenCaptureService, openAI: OpenAIService) {
        self.screenCapture = screenCapture
        self.openAI = openAI
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isProcessingTick = false
    }

    /// Fresh ambient context for JARVIS or see-capable local agents.
    var contextMessage: String? {
        guard enabled,
              let summary = latestSummary,
              let timestamp = latestSummaryAt,
              Date().timeIntervalSince(timestamp) <= JarvisConfig.perceptionContextMaxAge
        else {
            return nil
        }
        return "Current screen context: \(summary)"
    }

    private func startMonitoring() {
        stopMonitoring()
        timer = Timer.scheduledTimer(
            withTimeInterval: JarvisConfig.perceptionInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        tick()
    }

    private func tick() {
        guard enabled, !isProcessingTick else { return }
        isProcessingTick = true
        Task {
            defer { isProcessingTick = false }
            await performTick()
        }
    }

    private func performTick() async {
        guard enabled, openAI.hasKey else { return }

        if let lastVisionCall,
           Date().timeIntervalSince(lastVisionCall) < JarvisConfig.perceptionMinVisionInterval {
            return
        }

        let fingerprint: UInt64
        do {
            let thumbnail = try screenCapture.capturePerceptionFingerprint()
            fingerprint = averageHash(for: thumbnail)
        } catch {
            return
        }

        if let previous = lastFingerprint {
            let distance = hammingDistance(previous, fingerprint)
            if distance < JarvisConfig.perceptionChangeThreshold {
                return
            }
        }

        lastFingerprint = fingerprint

        do {
            let jpeg = try screenCapture.capturePerceptionVisionFrame()
            let base64 = screenCapture.jpegBase64(from: jpeg)
            let summary = try await openAI.ambientScreenSummary(jpegBase64: base64)
            latestSummary = summary
            latestSummaryAt = Date()
            lastVisionCall = Date()
        } catch {
            return
        }
    }

    private func averageHash(for image: CGImage) -> UInt64 {
        let side = 8
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return 0 }

        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side)
        var total = 0
        for index in 0..<(side * side) {
            total += Int(pixels[index])
        }
        let average = total / (side * side)

        var hash: UInt64 = 0
        for index in 0..<(side * side) {
            if Int(pixels[index]) >= average {
                hash |= (1 << UInt64(index))
            }
        }
        return hash
    }

    private func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}
