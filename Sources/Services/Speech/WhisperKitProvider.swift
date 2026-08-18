import Foundation
import WhisperKit

/// WhisperKit-based speech recognition provider.
///
/// Uses WhisperKit's AudioStreamTranscriber for real-time streaming recognition.
actor WhisperKitProvider: SpeechProvider {

    nonisolated let name = "WhisperKit"

    private var whisperKit: WhisperKit?
    private var audioStreamTranscriber: AudioStreamTranscriber?
    private var continuation: AsyncStream<[RecognizedWord]>.Continuation?
    private var _isListening = false

    // Deduplication state for streaming unconfirmed words
    // nonisolated(unsafe) because the stateCallback runs on WhisperKit's thread
    // and is called sequentially — no concurrent access.
    nonisolated(unsafe) private var lastConfirmedCount: Int = 0
    nonisolated(unsafe) private var lastUnconfirmedWordCount: Int = 0

    nonisolated var isListening: Bool { false }

    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func startListening() async throws -> AsyncStream<[RecognizedWord]> {
        debugLog("[WhisperKitProvider] startListening called")
        if whisperKit == nil {
            debugLog("[WhisperKitProvider] Loading WhisperKit...")
            whisperKit = try await modelManager.loadWhisperKit()
            debugLog("[WhisperKitProvider] WhisperKit loaded")
        }

        guard let kit = whisperKit else {
            debugLog("[WhisperKitProvider] ERROR: kit is nil after load")
            throw ProviderError.modelNotLoaded
        }

        _isListening = true
        lastConfirmedCount = 0
        lastUnconfirmedWordCount = 0

        let (stream, cont) = AsyncStream<[RecognizedWord]>.makeStream()
        self.continuation = cont

        let decodingOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en",
            temperature: 0.0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            firstTokenLogProbThreshold: -1.5,
            noSpeechThreshold: 0.6
        )

        let stateCallback: AudioStreamTranscriberCallback = { [weak self] _, newState in
            guard let self else { return }

            // --- 1. Handle newly confirmed segments (authoritative) ---
            let newConfirmedCount = newState.confirmedSegments.count

            if newConfirmedCount > self.lastConfirmedCount {
                let newSegments = Array(newState.confirmedSegments[self.lastConfirmedCount...])
                var words: [RecognizedWord] = []

                for segment in newSegments {
                    if let segmentWords = segment.words {
                        for word in segmentWords {
                            words.append(RecognizedWord(
                                text: word.word.trimmingCharacters(in: .whitespacesAndNewlines),
                                timestamp: TimeInterval(word.start),
                                confidence: word.probability
                            ))
                        }
                    } else {
                        let tokens = segment.text
                            .components(separatedBy: .whitespacesAndNewlines)
                            .filter { !$0.isEmpty }
                        for (i, token) in tokens.enumerated() {
                            words.append(RecognizedWord(
                                text: token,
                                timestamp: TimeInterval(segment.start) + Double(i) * 0.1,
                                confidence: segment.avgLogprob > -1.0 ? 0.8 : 0.5
                            ))
                        }
                    }
                }

                self.lastConfirmedCount = newConfirmedCount
                // Reset unconfirmed tracking — confirmed segments replace partials
                self.lastUnconfirmedWordCount = 0

                if !words.isEmpty {
                    debugLog("[WhisperKitProvider] CONFIRMED \(words.count) words: \(words.map(\.text).joined(separator: " "))")
                    Task { await self.yieldWords(words) }
                }
            }

            // --- 2. Stream unconfirmed segments (real-time partials) ---
            // Build the full unconfirmed text and diff against what we already yielded
            let unconfirmedText = newState.unconfirmedSegments
                .map(\.text)
                .joined(separator: " ")
            let allUnconfirmedWords = unconfirmedText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }

            let currentWordCount = allUnconfirmedWords.count

            if currentWordCount > self.lastUnconfirmedWordCount {
                // Only yield the NEW words we haven't seen before
                let newWords = Array(allUnconfirmedWords[self.lastUnconfirmedWordCount...])
                let now = Date().timeIntervalSinceReferenceDate

                let recognizedWords = newWords.enumerated().map { i, word in
                    RecognizedWord(
                        text: word.trimmingCharacters(in: .whitespacesAndNewlines),
                        timestamp: now + Double(i) * 0.05,
                        confidence: 0.6  // lower confidence for unconfirmed
                    )
                }

                self.lastUnconfirmedWordCount = currentWordCount

                if !recognizedWords.isEmpty {
                    debugLog("[WhisperKitProvider] STREAMING \(recognizedWords.count) words: \(recognizedWords.map(\.text).joined(separator: " "))")
                    Task { await self.yieldWords(recognizedWords) }
                }
            } else if currentWordCount < self.lastUnconfirmedWordCount {
                // WhisperKit revised its hypothesis (fewer words) — reset tracking
                // Don't yield anything; wait for it to stabilize
                self.lastUnconfirmedWordCount = currentWordCount
            }
        }

        // Build AudioStreamTranscriber from WhisperKit's components
        guard let tokenizer = kit.tokenizer else {
            throw ProviderError.modelNotLoaded
        }

        audioStreamTranscriber = AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: kit.audioProcessor,
            decodingOptions: decodingOptions,
            stateChangeCallback: stateCallback
        )

        debugLog("[WhisperKitProvider] Starting stream transcription in background...")

        // startStreamTranscription() blocks until streaming stops,
        // so run it in a detached task and return the stream immediately.
        let transcriber = audioStreamTranscriber
        Task.detached {
            do {
                try await transcriber?.startStreamTranscription()
                debugLog("[WhisperKitProvider] Stream transcription ended normally")
            } catch {
                debugLog("[WhisperKitProvider] Stream transcription error: \(error)")
            }
            await self.yieldFinished()
        }

        // Brief pause to let the audio engine spin up
        try await Task.sleep(for: .milliseconds(200))
        debugLog("[WhisperKitProvider] Stream transcription launched")

        return stream
    }

    private func yieldFinished() {
        continuation?.finish()
        continuation = nil
    }

    func stopListening() async {
        _isListening = false
        await audioStreamTranscriber?.stopStreamTranscription()
        audioStreamTranscriber = nil
        continuation?.finish()
        continuation = nil
        lastConfirmedCount = 0
        lastUnconfirmedWordCount = 0
    }

    private func yieldWords(_ words: [RecognizedWord]) {
        continuation?.yield(words)
    }

    enum ProviderError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "WhisperKit model not loaded"
            }
        }
    }
}
