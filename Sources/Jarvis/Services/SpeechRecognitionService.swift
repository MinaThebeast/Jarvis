import AVFoundation
import Speech
import Foundation

// MARK: - Events

enum SpeechEvent {
    case wakeWordDetected(command: String)
    case commandCaptureStarted
    case commandCaptureCancelled
    case abortRequested
    case audioLevel(Float)
    case permissionDenied(String)
    case recognitionError(Error)
}

// MARK: - Speech Recognition Service

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {

    // MARK: Public state
    @Published var isActive = false
    @Published var liveTranscript = ""

    var onEvent: ((SpeechEvent) -> Void)?

    // MARK: Private
    private let audioEngine    = AVAudioEngine()
    private let recognizer     = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private var restartTimer:       Timer?
    private var silenceTimer:       Timer?

    private enum ListeningState { case idle, awakened, recordingCommand }
    private var listeningState: ListeningState = .idle
    private var commandBuffer = ""

    // MARK: Permissions

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let mic: Bool
        if #available(macOS 14.0, *) {
            mic = await AVAudioApplication.requestRecordPermission()
        } else {
            mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        return speech && mic
    }

    // MARK: Start / Stop

    func start() async {
        let granted = await requestPermissions()
        guard granted else {
            onEvent?(.permissionDenied("Microphone or Speech Recognition permission denied. Please enable in System Settings."))
            return
        }

        guard recognizer?.isAvailable == true else {
            onEvent?(.recognitionError(SpeechError.recognizerUnavailable))
            return
        }

        isActive = true
        listeningState = .idle
        commandBuffer = ""

        beginSession()
        scheduleRestart()
    }

    func stop() {
        isActive = false
        isPaused = false
        cancelSession()
        invalidateTimers()
    }

    func pauseListening() {
        guard isActive, !isPaused else { return }
        isPaused = true
        cancelSession()
        invalidateTimers()
    }

    func resumeListening() {
        guard isActive, isPaused else { return }
        isPaused = false
        listeningState = .idle
        commandBuffer = ""
        liveTranscript = ""
        beginSession()
        scheduleRestart()
    }

    // MARK: Private state

    private var isPaused = false

    // MARK: Session management

    private func beginSession() {
        cancelSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<frameLength { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameLength))
            let normalized = min(rms * 60, 1.0)

            Task { @MainActor [weak self] in
                self?.onEvent?(.audioLevel(normalized))
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            onEvent?(.recognitionError(error))
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                Task { @MainActor [weak self] in
                    self?.handleTranscription(text, isFinal: isFinal)
                }
            }

            if let error {
                let nsErr = error as NSError
                if nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 216 { return }
                if nsErr.code == 1110 { return }
                Task { @MainActor [weak self] in
                    self?.onEvent?(.recognitionError(error))
                }
            }
        }
    }

    private func cancelSession() {
        invalidateTimers()

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func scheduleRestart() {
        restartTimer?.invalidate()
        let timer = Timer(
            timeInterval: JarvisConfig.recognitionRestartInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, !self.isPaused else { return }
                guard self.listeningState == .idle else { return }
                self.beginSession()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        restartTimer = timer
    }

    // MARK: Transcript Processing

    private func handleTranscription(_ rawText: String, isFinal: Bool) {
        let text = rawText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        liveTranscript = rawText

        for phrase in JarvisConfig.abortPhrases {
            if text.contains(phrase) {
                resetCapture()
                onEvent?(.abortRequested)
                return
            }
        }

        switch listeningState {

        case .idle:
            guard let (_, afterWake) = matchWakeWord(in: text) else { return }

            if afterWake.isEmpty {
                listeningState = .awakened
                onEvent?(.wakeWordDetected(command: ""))
                armSilenceTimer()
            } else {
                beginRecordingCommand(afterWake)
                if isFinal { dispatchCommand() }
            }

        case .awakened:
            let command = stripWakeWords(from: text)
            guard !command.isEmpty else {
                if isFinal { cancelCapture() }
                return
            }
            beginRecordingCommand(command)
            if isFinal { dispatchCommand() }

        case .recordingCommand:
            let command = stripWakeWords(from: text)
            guard !command.isEmpty else { return }
            commandBuffer = command
            armSilenceTimer()
            if isFinal { dispatchCommand() }
        }
    }

    private func matchWakeWord(in text: String) -> (String, String)? {
        for wakeWord in JarvisConfig.wakeWords {
            if let range = text.range(of: wakeWord) {
                let afterWake = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (wakeWord, afterWake)
            }
        }
        return nil
    }

    private func beginRecordingCommand(_ command: String) {
        listeningState = .recordingCommand
        commandBuffer = command
        onEvent?(.commandCaptureStarted)
        armSilenceTimer()
    }

    private func stripWakeWords(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for wakeWord in JarvisConfig.wakeWords {
            if let range = result.range(of: wakeWord) {
                result = String(result[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        let interval = listeningState == .awakened
            ? JarvisConfig.wakeCommandTimeoutSeconds
            : JarvisConfig.silenceThresholdSeconds

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSilenceTimeout()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }

    private func handleSilenceTimeout() {
        switch listeningState {
        case .awakened:
            cancelCapture()
        case .recordingCommand:
            dispatchCommand()
        case .idle:
            break
        }
    }

    private func dispatchCommand() {
        guard listeningState == .recordingCommand else { return }
        guard !commandBuffer.isEmpty else {
            cancelCapture()
            return
        }

        silenceTimer?.invalidate()
        silenceTimer = nil

        let command = commandBuffer
        resetCapture()
        onEvent?(.wakeWordDetected(command: command))
    }

    private func cancelCapture() {
        resetCapture()
        onEvent?(.commandCaptureCancelled)
    }

    private func resetCapture() {
        listeningState = .idle
        commandBuffer = ""
    }

    private func invalidateTimers() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        restartTimer?.invalidate()
        restartTimer = nil
    }
}

// MARK: - Errors

enum SpeechError: Error, LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        "Speech recognizer is not available on this device."
    }
}
