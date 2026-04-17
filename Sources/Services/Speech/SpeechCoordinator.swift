import Foundation

/// Coordinates speech recognition providers and feeds the tracking engine.
///
/// This is the main observable layer that views bind to. It owns the active
/// provider, manages its lifecycle, and wires speech output to the engine.
@Observable
final class SpeechCoordinator {

    enum ProviderType: String, CaseIterable {
        case whisperKit = "WhisperKit"
        case appleSpeech = "Apple Speech"
    }

    // MARK: - Observable State

    private(set) var isListening: Bool = false
    private(set) var currentProviderType: ProviderType = .appleSpeech
    private(set) var error: String?
    private(set) var wordCount: Int = 0
    private(set) var lastHeardWords: String = ""
    /// Brief notification when falling back to alternate provider.
    private(set) var fallbackMessage: String?

    // MARK: - Dependencies

    let engine: SpeechToScrollEngine
    let modelManager: ModelManager

    // MARK: - Private

    private var activeProvider: (any SpeechProvider)?
    private var listeningTask: Task<Void, Never>?
    private var whisperKitProvider: WhisperKitProvider?
    private var appleSpeechProvider: AppleSpeechProvider?

    init(engine: SpeechToScrollEngine, modelManager: ModelManager) {
        self.engine = engine
        self.modelManager = modelManager
    }

    // MARK: - Public API

    /// Start listening with the current provider type.
    /// Falls back to Apple Speech if the primary provider fails.
    func startListening() {
        guard !isListening else { return }
        error = nil
        fallbackMessage = nil

        debugLog("[SpeechCoordinator] startListening — provider: \(currentProviderType.rawValue)")

        listeningTask = Task { @MainActor in
            do {
                try await startWithProvider(type: currentProviderType)
            } catch {
                debugLog("[SpeechCoordinator] \(currentProviderType.rawValue) failed: \(error)")
                // Fall back to the other provider
                let fallback: ProviderType =
                    currentProviderType == .appleSpeech ? .whisperKit : .appleSpeech
                self.fallbackMessage = "Switching to \(fallback.rawValue)..."
                self.error =
                    "\(currentProviderType.rawValue) failed, trying \(fallback.rawValue)..."
                do {
                    try await startWithProvider(type: fallback)
                    self.fallbackMessage = "Using \(fallback.rawValue)"
                    self.error =
                        "Using \(fallback.rawValue) (\(currentProviderType.rawValue) unavailable)"
                    // Auto-clear fallback message after a few seconds
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(5))
                        self.fallbackMessage = nil
                    }
                } catch {
                    debugLog("[SpeechCoordinator] \(fallback.rawValue) also failed: \(error)")
                    self.error = "Speech failed: \(error.localizedDescription)"
                    self.fallbackMessage = nil
                    self.isListening = false
                }
            }
        }
    }

    private func startWithProvider(type: ProviderType) async throws {
        debugLog("[SpeechCoordinator] Starting provider: \(type.rawValue)")
        let provider = try await createProvider(type: type)
        self.activeProvider = provider

        let stream = try await provider.startListening()
        self.isListening = true
        debugLog("[SpeechCoordinator] \(type.rawValue) listening — waiting for words...")

        var receivedAnyWords = false
        let streamStartTime = Date()

        for await words in stream {
            guard self.isListening else { break }
            receivedAnyWords = true
            self.wordCount += words.count
            self.lastHeardWords = words.map(\.text).joined(separator: " ")
            debugLog("[SpeechCoordinator] Heard \(words.count) words: \(self.lastHeardWords)")
            self.engine.processWords(words)
        }

        debugLog(
            "[SpeechCoordinator] \(type.rawValue) stream ended (receivedWords=\(receivedAnyWords))")
        self.isListening = false

        // If the stream ended very quickly with no words, this is a fatal provider error
        // (e.g., "Siri and Dictation are disabled"). Throw to trigger fallback.
        let streamDuration = Date().timeIntervalSince(streamStartTime)
        if !receivedAnyWords && streamDuration < 10 {
            throw CoordinatorError.providerStreamEndedEarly(provider: type.rawValue)
        }
    }

    enum CoordinatorError: LocalizedError {
        case providerStreamEndedEarly(provider: String)

        var errorDescription: String? {
            switch self {
            case .providerStreamEndedEarly(let provider):
                return "\(provider) stopped without producing any results"
            }
        }
    }

    /// Stop listening.
    func stopListening() {
        isListening = false
        listeningTask?.cancel()
        listeningTask = nil

        Task {
            await activeProvider?.stopListening()
            activeProvider = nil
        }
    }

    /// Switch to a different provider type.
    func switchProvider(to type: ProviderType) {
        let wasListening = isListening
        if wasListening {
            stopListening()
        }
        currentProviderType = type
        if wasListening {
            startListening()
        }
    }

    // MARK: - Simulated Speech (Debug)

    private var simulationTask: Task<Void, Never>?

    /// Feed the engine words from the loaded script on a timer.
    /// Bypasses speech recognition entirely for testing scroll/highlight.
    func startSimulating(words: [String], wordsPerSecond: Double = 3.0) {
        guard !isListening else { return }
        isListening = true
        error = "Simulated speech"
        debugLog(
            "[SpeechCoordinator] Starting simulated speech: \(words.count) words at \(wordsPerSecond) wps"
        )

        let interval = 1.0 / wordsPerSecond
        simulationTask = Task { @MainActor in
            for (i, word) in words.enumerated() {
                guard self.isListening else { break }
                let rw = RecognizedWord(
                    text: word, timestamp: TimeInterval(i) * interval, confidence: 1.0)
                self.wordCount += 1
                self.lastHeardWords = word
                self.engine.processWords([rw])

                if i % 20 == 0 {
                    debugLog(
                        "[Sim] word \(i)/\(words.count): \"\(word)\" cursor=\(self.engine.scrollPosition)"
                    )
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            debugLog("[SpeechCoordinator] Simulation complete")
            self.isListening = false
        }
    }

    func stopSimulating() {
        simulationTask?.cancel()
        simulationTask = nil
        isListening = false
    }

    // MARK: - Provider Creation

    private func createProvider(type: ProviderType) async throws -> any SpeechProvider {
        switch type {
        case .whisperKit:
            if whisperKitProvider == nil {
                whisperKitProvider = WhisperKitProvider(modelManager: modelManager)
            }
            return whisperKitProvider!

        case .appleSpeech:
            if appleSpeechProvider == nil {
                appleSpeechProvider = AppleSpeechProvider()
            }
            return appleSpeechProvider!
        }
    }
}
