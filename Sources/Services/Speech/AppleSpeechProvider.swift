import AVFoundation
import Foundation
import Speech

/// Apple SFSpeechRecognizer-based fallback provider.
///
/// Uses on-device recognition when available. Handles the 1-minute session
/// limit by automatically rotating recognition tasks.
actor AppleSpeechProvider: SpeechProvider {

    nonisolated let name = "Apple Speech"

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var continuation: AsyncStream<[RecognizedWord]>.Continuation?
    private var _isListening = false
    private var sessionStartTime: Date?
    // nonisolated(unsafe) because the recognition callback runs on SFSpeechRecognizer's
    // thread and is called sequentially — no concurrent access.
    nonisolated(unsafe) private var lastProcessedSegmentCount: Int = 0
    // Set on fatal error to prevent any session restarts (also accessed from callback thread)
    nonisolated(unsafe) private var hasFatalError: Bool = false

    // Session rotation: Apple limits recognition to ~1 minute
    private let maxSessionDuration: TimeInterval = 55
    // If on-device fails (requires Siri), fall back to server-based recognition
    private var forceServerRecognition: Bool = false
    // Watchdog: restart session if no words arrive for this long
    private let silenceWatchdogTimeout: TimeInterval = 8
    // Accessed from recognition callback thread (same sequential access pattern as lastProcessedSegmentCount)
    nonisolated(unsafe) private var lastWordTime: Date = Date()
    private var watchdogTimer: Task<Void, Never>?
    // Guard against re-entrant session rotation
    private var isRotating: Bool = false

    nonisolated var isListening: Bool { false }

    func startListening() async throws -> AsyncStream<[RecognizedWord]> {
        // Check authorization status without prompting — permissions are
        // handled centrally by PermissionManager during onboarding or
        // before presenting.
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        debugLog("[AppleSpeech] Auth status: \(authStatus.rawValue)")
        guard authStatus == .authorized else {
            throw ProviderError.notAuthorized
        }

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            debugLog("[AppleSpeech] Recognizer unavailable")
            throw ProviderError.unavailable
        }
        debugLog(
            "[AppleSpeech] Recognizer available. onDevice=\(recognizer.supportsOnDeviceRecognition)"
        )

        // Prefer on-device recognition
        if recognizer.supportsOnDeviceRecognition {
            recognizer.defaultTaskHint = .dictation
        }

        _isListening = true
        hasFatalError = false
        isRotating = false

        let (stream, cont) = AsyncStream<[RecognizedWord]>.makeStream()
        self.continuation = cont

        // Start persistent audio engine — kept alive across session rotations
        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        engine.prepare()
        try engine.start()
        debugLog("[AppleSpeech] Audio engine started, format: \(recordingFormat)")

        startRecognitionTask()
        return stream
    }

    func stopListening() async {
        _isListening = false
        stopWatchdog()
        stopRecognitionTask()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Session Management

    /// Start a new recognition task on the existing audio engine.
    private func startRecognitionTask() {
        guard let audioEngine, let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if forceServerRecognition {
            request.requiresOnDeviceRecognition = false
            debugLog("[AppleSpeech] Using server-based recognition")
        } else {
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            debugLog("[AppleSpeech] Using on-device=\(request.requiresOnDeviceRecognition)")
        }

        self.recognitionRequest = request
        self.sessionStartTime = Date()
        self.lastWordTime = Date()
        self.lastProcessedSegmentCount = 0

        // Install a fresh tap to feed buffers to this request
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        startWatchdog()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, !self.hasFatalError else { return }

            if let result {
                let segments = result.bestTranscription.segments
                let newCount = segments.count

                if newCount > self.lastProcessedSegmentCount {
                    let newSegments = segments[self.lastProcessedSegmentCount..<newCount]
                    let words: [RecognizedWord] = newSegments.map { segment in
                        RecognizedWord(
                            text: segment.substring,
                            timestamp: segment.timestamp,
                            confidence: Float(segment.confidence)
                        )
                    }
                    self.lastProcessedSegmentCount = newCount

                    if !words.isEmpty {
                        debugLog(
                            "[AppleSpeech] +\(words.count) words: \(words.map(\.text).joined(separator: " "))"
                        )
                        self.lastWordTime = Date()
                        Task { await self.yieldWords(words) }
                    }
                } else if newCount < self.lastProcessedSegmentCount {
                    self.lastProcessedSegmentCount = newCount
                }
            }

            if let error {
                let nsError = error as NSError
                debugLog(
                    "[AppleSpeech] Error: \(nsError.localizedDescription) (domain=\(nsError.domain) code=\(nsError.code))"
                )
                if nsError.code == 1110 {
                    // "No speech detected" — normal timeout, rotate
                    Task { await self.rotateSession() }
                } else if nsError.code == 301 || nsError.code == 216 {
                    // 301 = "request was canceled" (we caused it during rotation)
                    // 216 = "task was canceled" — same idea
                    debugLog("[AppleSpeech] Ignoring cancellation error (rotation in progress)")
                } else if nsError.localizedDescription.contains("Siri")
                    || nsError.localizedDescription.contains("Dictation")
                {
                    debugLog("[AppleSpeech] On-device failed, retrying with server recognition...")
                    Task { await self.retryWithServerRecognition() }
                } else {
                    debugLog("[AppleSpeech] Fatal error, stopping provider permanently")
                    self.hasFatalError = true
                    Task { await self.handleFatalError() }
                }
            } else if result?.isFinal == true {
                Task { await self.rotateSession() }
            }
        }
    }

    private func yieldWords(_ words: [RecognizedWord]) {
        continuation?.yield(words)
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)  // check every 3s
                guard !Task.isCancelled, let self else { return }
                await self.watchdogCheck()
            }
        }
    }

    private func watchdogCheck() {
        guard _isListening, !hasFatalError, !isRotating else { return }
        let silence = Date().timeIntervalSince(lastWordTime)
        let sessionAge = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0

        if silence > silenceWatchdogTimeout {
            debugLog("[AppleSpeech] Watchdog: \(Int(silence))s silence — rotating session")
            rotateSession()
        } else if sessionAge > maxSessionDuration {
            debugLog("[AppleSpeech] Watchdog: session age \(Int(sessionAge))s — rotating")
            rotateSession()
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    // MARK: - Session Rotation

    /// Rotate the recognition task while keeping the audio engine running.
    private func rotateSession() {
        guard _isListening, !hasFatalError, !isRotating else { return }
        isRotating = true

        debugLog("[AppleSpeech] Rotating recognition session...")
        stopWatchdog()
        stopRecognitionTask()

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms gap
            guard self._isListening, !self.hasFatalError else {
                self.isRotating = false
                return
            }
            self.isRotating = false
            self.startRecognitionTask()
            debugLog("[AppleSpeech] New session started")
        }
    }

    private func retryWithServerRecognition() {
        guard _isListening, !hasFatalError, !forceServerRecognition else {
            debugLog("[AppleSpeech] Server retry not possible, stopping")
            handleFatalError()
            return
        }
        forceServerRecognition = true
        isRotating = true
        stopWatchdog()
        stopRecognitionTask()
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard self._isListening, !self.hasFatalError else {
                self.isRotating = false
                return
            }
            self.isRotating = false
            self.startRecognitionTask()
        }
    }

    private func handleFatalError() {
        _isListening = false
        stopWatchdog()
        stopRecognitionTask()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        continuation?.finish()
        continuation = nil
    }

    /// Stop only the recognition task/request — leave audio engine running.
    private func stopRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    // MARK: - Authorization (read-only)

    enum ProviderError: LocalizedError {
        case notAuthorized
        case unavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Speech recognition not authorized"
            case .unavailable: return "Speech recognition unavailable"
            }
        }
    }
}
