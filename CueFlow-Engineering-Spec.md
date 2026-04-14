# CueFlow — Engineering Specification

**Version:** 0.3 (Engineering-Ready — WhisperKit)
**Author:** Jacob
**Date:** March 30, 2026
**Status:** Ready for Claude Code implementation

---

## 1. Product Overview

CueFlow is a macOS-native smart teleprompter that pulls speaker notes from Google Slides, shows slide thumbnails alongside the script, and uses voice recognition to pace scrolling to your natural speech.

**One-line pitch:** The teleprompter that knows what slide you're on.

**Target users:** Remote professionals presenting on camera — PMs, sales engineers, founders, consultants — who already have decks in Google Slides.

**Competitive wedge:** No Mac teleprompter connects to Google Slides today. CueFlow is presentation-aware, not just a text scroller.

---

## 2. Project Structure

```
CueFlow/
├── CueFlow.xcodeproj
├── CueFlow/
│   ├── App/
│   │   ├── CueFlowApp.swift              # @main entry point, app lifecycle
│   │   ├── AppDelegate.swift              # NSApplicationDelegate for window management
│   │   └── AppState.swift                 # Global app state (ObservableObject)
│   │
│   ├── Models/
│   │   ├── Presentation.swift             # Presentation, Slide, SpeakerNotes models
│   │   ├── Script.swift                   # Freeform script model (non-Slides content)
│   │   ├── PrompterState.swift            # Current scroll position, active slide, playback state
│   │   ├── WindowPreset.swift             # Position presets enum + custom positions
│   │   └── AppSettings.swift              # All user-configurable settings (Codable)
│   │
│   ├── Services/
│   │   ├── Speech/
│   │   │   ├── SpeechProvider.swift              # Protocol abstracting speech engines
│   │   │   ├── WhisperKitProvider.swift           # Primary: WhisperKit (Whisper via CoreML/ANE)
│   │   │   ├── AppleSpeechProvider.swift          # Fallback: SFSpeechRecognizer for Intel Macs
│   │   │   ├── SpeechToScrollEngine.swift        # Fuzzy matching algorithm (speech → scroll position)
│   │   │   ├── AudioLevelMonitor.swift           # RMS level tracking for voice beam visualization
│   │   │   └── ModelManager.swift                # WhisperKit model download, storage, selection
│   │   │
│   │   ├── Google/
│   │   │   ├── GoogleAuthService.swift           # OAuth 2.0 via ASWebAuthenticationSession
│   │   │   ├── GoogleSlidesService.swift         # Slides API: fetch presentation, notes, thumbnails
│   │   │   └── GoogleDriveService.swift          # Drive API: list recent presentations
│   │   │
│   │   ├── WindowManager.swift            # NSPanel creation, positioning, screen-share exclusion
│   │   └── StorageService.swift           # Local persistence (SwiftData or UserDefaults + FileManager)
│   │
│   ├── ViewModels/
│   │   ├── PrompterViewModel.swift        # Drives the prompter overlay UI
│   │   ├── EditorViewModel.swift          # Script editor state
│   │   ├── SlidesImportViewModel.swift    # Google Slides browser/import flow
│   │   └── SettingsViewModel.swift        # Settings bindings
│   │
│   ├── Views/
│   │   ├── Prompter/
│   │   │   ├── PrompterOverlayView.swift         # Main prompter text display
│   │   │   ├── SlideThumbnailView.swift           # Current slide thumbnail sidebar
│   │   │   ├── VoiceBeamView.swift                # Audio level visualization
│   │   │   ├── CountdownView.swift                # Pre-start countdown overlay
│   │   │   └── PrompterStatusBar.swift            # Slide number, elapsed time, minimal chrome
│   │   │
│   │   ├── Editor/
│   │   │   ├── ScriptEditorView.swift             # Rich text editor for freeform scripts
│   │   │   └── SectionMarkerView.swift            # Visual dividers between script sections
│   │   │
│   │   ├── Import/
│   │   │   ├── SlidesPickerView.swift             # Google Slides file browser
│   │   │   └── SlidePreviewGrid.swift             # Thumbnail grid after import
│   │   │
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift                 # Main settings window (tabbed)
│   │   │   ├── AppearanceSettingsView.swift
│   │   │   ├── BehaviorSettingsView.swift
│   │   │   ├── PresentationSettingsView.swift
│   │   │   └── WindowSettingsView.swift
│   │   │
│   │   └── Onboarding/
│   │       ├── WelcomeView.swift
│   │       ├── MicPermissionView.swift
│   │       └── GoogleConnectView.swift
│   │
│   ├── Utilities/
│   │   ├── FuzzyMatcher.swift             # Levenshtein + token-level fuzzy matching
│   │   ├── KeychainHelper.swift           # Keychain read/write for OAuth tokens
│   │   ├── ScreenDetector.swift           # Enumerate displays, detect notch presence
│   │   └── Constants.swift                # API keys, URLs, default values
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── GoogleService-Info.plist       # Google OAuth client config
│   │   └── Info.plist                     # Privacy usage descriptions
│   │
│   └── Entitlements/
│       └── CueFlow.entitlements           # Network, microphone, keychain entitlements
│
├── CueFlowTests/
│   ├── SpeechToScrollEngineTests.swift    # Unit tests for fuzzy matching algorithm
│   ├── FuzzyMatcherTests.swift            # Edge cases: homophones, skipped words, ad-libs
│   ├── WhisperKitProviderTests.swift      # Model loading, transcription result parsing
│   ├── GoogleSlidesServiceTests.swift     # Mock API response parsing
│   └── PrompterViewModelTests.swift       # State machine transitions
│
├── Package.swift                          # SPM dependencies (WhisperKit, etc.)
│
└── README.md
```

---

## 3. Core Technical Implementation

### 3.1 Speech Recognition — WhisperKit + Provider Abstraction

**Framework choice:** Use **WhisperKit** (by Argmax) as the primary speech engine. WhisperKit compiles OpenAI's Whisper models to CoreML and runs them on Apple's Neural Engine (ANE), providing significantly better accuracy than `SFSpeechRecognizer` for continuous speech. This matters because higher recognition accuracy directly reduces false positives in the speech-to-scroll fuzzy matching.

**Why WhisperKit over SFSpeechRecognizer:**
- **No session rotation hacks.** SFSpeechRecognizer degrades over long sessions and requires a 55-second restart workaround. WhisperKit processes audio in natural chunks — no artificial limits.
- **No Apple throttling.** SFSpeechRecognizer has vague, undocumented rate limits even in on-device mode. WhisperKit runs your model on your hardware with zero gatekeeping.
- **Word-level timestamps.** WhisperKit provides per-segment timestamps that map directly to the speech-to-scroll cursor.
- **Better accuracy for continuous speech.** Whisper `base.en` matches or exceeds SFSpeechRecognizer on-device for English; `small.en` is substantially better.

**Why keep SFSpeechRecognizer as a fallback:**
- Intel Macs have no Neural Engine — WhisperKit runs on CPU, which is slow for larger models. SFSpeechRecognizer is acceptable as a fallback.
- Zero download cost — useful for users who want to start immediately without waiting for model download.

**Model sizing:**

| Model | Size on disk | Relative speed (M1) | Accuracy (WER) | Recommended for |
|-------|-------------|---------------------|-----------------|-----------------|
| `tiny.en` | ~40 MB | ~30x realtime | Good | Quick start / low-end machines |
| `base.en` | ~150 MB | ~15x realtime | Very good | **Default — best speed/accuracy balance** |
| `small.en` | ~500 MB | ~6x realtime | Excellent | Users who want max accuracy |

**Dependency:** Add WhisperKit via Swift Package Manager:
```swift
// Package.swift or Xcode > File > Add Package Dependencies
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
]
```

---

#### 3.1.1 SpeechProvider Protocol

All speech engines conform to this protocol. The `SpeechToScrollEngine` depends only on `SpeechProvider`, never on a concrete implementation.

**Implementation: `SpeechProvider.swift`**

```swift
import Foundation
import AVFoundation
import Combine

/// A recognized word with timing and confidence metadata
struct RecognizedWord {
    let text: String
    let timestamp: TimeInterval  // Seconds from start of listening session
    let confidence: Float        // 0.0–1.0 (1.0 = highest confidence)
}

/// Errors common across speech providers
enum SpeechProviderError: Error, LocalizedError {
    case notAuthorized
    case notAvailable(reason: String)
    case modelNotLoaded
    case audioEngineFailure(Error)
    case providerSpecific(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Microphone or speech recognition permission denied."
        case .notAvailable(let reason): return "Speech recognition unavailable: \(reason)"
        case .modelNotLoaded: return "Speech model not loaded. Please download a model first."
        case .audioEngineFailure(let err): return "Audio engine error: \(err.localizedDescription)"
        case .providerSpecific(let err): return err.localizedDescription
        }
    }
}

/// Abstract interface for speech recognition engines.
/// Consumers (SpeechToScrollEngine) depend only on this protocol.
@MainActor
protocol SpeechProvider: ObservableObject {
    /// Whether the provider is currently processing audio
    var isListening: Bool { get }
    
    /// Current audio input level (0.0–1.0) for voice beam visualization
    var audioLevel: Float { get }
    
    /// Human-readable name for settings UI (e.g. "WhisperKit (base.en)")
    var displayName: String { get }
    
    /// Whether the provider is ready (model loaded, permissions granted)
    var isReady: Bool { get }
    
    /// Callback: emits newly recognized words. Set by SpeechToScrollEngine.
    var onWordsRecognized: (([RecognizedWord]) -> Void)? { get set }
    
    /// Request required permissions (mic, speech recognition)
    func requestAuthorization() async -> Bool
    
    /// Prepare the provider (download/load model if needed). May be long-running.
    func prepare() async throws
    
    /// Begin listening and recognizing speech from the microphone
    func startListening() throws
    
    /// Stop listening and clean up audio resources
    func stopListening()
}
```

---

#### 3.1.2 WhisperKit Provider (Primary)

**Implementation: `WhisperKitProvider.swift`**

```swift
import WhisperKit
import AVFoundation
import Combine

@MainActor
class WhisperKitProvider: ObservableObject, SpeechProvider {
    
    // MARK: - SpeechProvider conformance
    @Published var isListening = false
    @Published var audioLevel: Float = 0.0
    @Published var isReady = false
    
    var displayName: String {
        "WhisperKit (\(selectedModel))"
    }
    
    var onWordsRecognized: (([RecognizedWord]) -> Void)?
    
    // MARK: - Configuration
    private let modelManager: ModelManager
    private var selectedModel: String  // e.g. "base.en", "small.en"
    
    // MARK: - WhisperKit internals
    private var whisperKit: WhisperKit?
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []       // Accumulated 16kHz mono samples
    private var sessionStartTime: Date = Date()
    
    // MARK: - Streaming parameters
    /// How many seconds of audio to accumulate before running inference.
    /// Shorter = more responsive but higher CPU usage. 2s is a good balance.
    private let chunkDuration: TimeInterval = 2.0
    
    /// Overlap between chunks to avoid splitting words at boundaries.
    private let chunkOverlap: TimeInterval = 0.5
    
    /// Target sample rate for Whisper (always 16kHz)
    private let targetSampleRate: Double = 16000.0
    
    /// Tracks words already emitted to avoid duplicates across chunks
    private var lastEmittedText: String = ""
    
    /// Timer that triggers chunk processing
    private var inferenceTimer: Timer?
    
    init(modelManager: ModelManager, model: String = "base.en") {
        self.modelManager = modelManager
        self.selectedModel = model
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        // WhisperKit only needs microphone permission (no SFSpeechRecognizer auth)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
    
    // MARK: - Prepare (Model Loading)
    
    func prepare() async throws {
        // Ensure model is downloaded
        let modelPath = try await modelManager.ensureModelAvailable(selectedModel)
        
        // Initialize WhisperKit with the local model
        let config = WhisperKitConfig(
            model: selectedModel,
            modelFolder: modelPath,
            verbose: false,
            prewarm: true      // Pre-warm the Neural Engine for faster first inference
        )
        
        self.whisperKit = try await WhisperKit(config)
        self.isReady = true
    }
    
    // MARK: - Start Listening
    
    func startListening() throws {
        guard let _ = whisperKit else {
            throw SpeechProviderError.modelNotLoaded
        }
        
        stopListening() // Clean up any prior session
        
        sessionStartTime = Date()
        audioBuffer = []
        lastEmittedText = ""
        
        // Configure audio engine to capture mic at 16kHz mono Float32
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        // We'll capture in native format and resample in the tap handler
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, nativeRate: nativeFormat.sampleRate)
        }
        
        try audioEngine.start()
        isListening = true
        
        // Start periodic inference
        inferenceTimer = Timer.scheduledTimer(
            withTimeInterval: chunkDuration - chunkOverlap,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.runInference()
            }
        }
    }
    
    // MARK: - Stop Listening
    
    func stopListening() {
        inferenceTimer?.invalidate()
        inferenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
        audioBuffer = []
    }
    
    // MARK: - Audio Processing
    
    /// Downsample incoming audio to 16kHz mono and accumulate in buffer.
    /// Also compute RMS for voice beam visualization.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, nativeRate: Double) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Compute RMS for audio level meter
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(frameCount))
        let normalizedLevel = min(max(rms * 5.0, 0.0), 1.0)
        Task { @MainActor in self.audioLevel = normalizedLevel }
        
        // Resample to 16kHz if needed
        if abs(nativeRate - targetSampleRate) < 1.0 {
            // Already 16kHz (unlikely but handle it)
            audioBuffer.append(contentsOf: samples)
        } else {
            // Simple linear interpolation downsampling
            let ratio = targetSampleRate / nativeRate
            let outputCount = Int(Double(frameCount) * ratio)
            var resampled = [Float](repeating: 0, count: outputCount)
            for i in 0..<outputCount {
                let srcIndex = Double(i) / ratio
                let srcFloor = Int(srcIndex)
                let frac = Float(srcIndex - Double(srcFloor))
                let s0 = samples[min(srcFloor, frameCount - 1)]
                let s1 = samples[min(srcFloor + 1, frameCount - 1)]
                resampled[i] = s0 + frac * (s1 - s0)
            }
            audioBuffer.append(contentsOf: resampled)
        }
        
        // Cap buffer at 30 seconds to prevent unbounded memory growth
        let maxSamples = Int(targetSampleRate * 30.0)
        if audioBuffer.count > maxSamples {
            audioBuffer = Array(audioBuffer.suffix(maxSamples))
        }
    }
    
    // MARK: - Inference
    
    /// Run Whisper inference on the accumulated audio buffer.
    /// Called periodically by inferenceTimer.
    private func runInference() async {
        guard let whisperKit = whisperKit, isListening else { return }
        
        // Take a chunk from the buffer (last chunkDuration seconds)
        let chunkSamples = Int(targetSampleRate * chunkDuration)
        guard audioBuffer.count >= chunkSamples / 2 else { return } // Wait for enough audio
        
        let chunk: [Float]
        if audioBuffer.count >= chunkSamples {
            chunk = Array(audioBuffer.suffix(chunkSamples))
        } else {
            chunk = audioBuffer
        }
        
        do {
            // WhisperKit transcribe expects [Float] of 16kHz mono audio
            let result = try await whisperKit.transcribe(audioArray: chunk)
            
            guard let transcription = result.first else { return }
            
            // Extract word-level segments
            let segments = transcription.segments
            let fullText = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Deduplicate: only emit words not already emitted
            guard fullText != lastEmittedText, !fullText.isEmpty else { return }
            
            // Find new text by comparing with last emitted
            let newWords = extractNewWords(fullText: fullText, previousText: lastEmittedText)
            lastEmittedText = fullText
            
            if !newWords.isEmpty {
                // Build RecognizedWord array with approximate timestamps
                let chunkStartTime = Date().timeIntervalSince(sessionStartTime) - chunkDuration
                let wordsPerSecond = Double(newWords.count) / chunkDuration
                
                let recognized = newWords.enumerated().map { index, word in
                    RecognizedWord(
                        text: word,
                        timestamp: chunkStartTime + Double(index) / max(wordsPerSecond, 1.0),
                        confidence: 0.85 // WhisperKit doesn't expose per-word confidence; use segments if available
                    )
                }
                
                onWordsRecognized?(recognized)
            }
            
        } catch {
            print("[WhisperKitProvider] Inference error: \(error)")
            // Don't stop listening on transient errors — just skip this chunk
        }
    }
    
    /// Given the full text from the latest chunk and the previously emitted text,
    /// return only the genuinely new words.
    private func extractNewWords(fullText: String, previousText: String) -> [String] {
        let fullWords = fullText.split(separator: " ").map(String.init)
        let prevWords = previousText.split(separator: " ").map(String.init)
        
        // Find the longest suffix of prevWords that matches a prefix of fullWords
        // (because chunk overlap means some words repeat)
        var overlapLength = 0
        for len in stride(from: min(prevWords.count, fullWords.count), through: 1, by: -1) {
            let prevSuffix = prevWords.suffix(len)
            let fullPrefix = fullWords.prefix(len)
            if Array(prevSuffix) == Array(fullPrefix) {
                overlapLength = len
                break
            }
        }
        
        return Array(fullWords.dropFirst(overlapLength))
    }
    
    // MARK: - Model Switching
    
    func switchModel(to model: String) async throws {
        let wasListening = isListening
        if wasListening { stopListening() }
        
        self.selectedModel = model
        self.isReady = false
        try await prepare()
        
        if wasListening { try startListening() }
    }
}
```

---

#### 3.1.3 Apple Speech Provider (Fallback for Intel Macs)

**Implementation: `AppleSpeechProvider.swift`**

```swift
import Speech
import AVFoundation
import Combine

/// Fallback provider using Apple's SFSpeechRecognizer.
/// Used on Intel Macs where WhisperKit runs too slowly on CPU.
@MainActor
class AppleSpeechProvider: ObservableObject, SpeechProvider {
    
    @Published var isListening = false
    @Published var audioLevel: Float = 0.0
    @Published var isReady = false
    
    var displayName: String { "Apple Speech (On-Device)" }
    var onWordsRecognized: (([RecognizedWord]) -> Void)?
    
    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastProcessedWordCount = 0
    
    // Session rotation: SFSpeechRecognizer degrades over long sessions.
    // Restart every 55 seconds, carrying over context seamlessly.
    private var sessionRotationTimer: Timer?
    private let sessionRotationInterval: TimeInterval = 55.0
    
    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()!
    }
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    func prepare() async throws {
        guard speechRecognizer.isAvailable else {
            throw SpeechProviderError.notAvailable(reason: "SFSpeechRecognizer not available on this device.")
        }
        isReady = true
    }
    
    func startListening() throws {
        guard isReady else { throw SpeechProviderError.modelNotLoaded }
        stopListening()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // No duration/rate limits on-device
        self.recognitionRequest = request
        self.lastProcessedWordCount = 0
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }
        
        try audioEngine.start()
        startRecognitionTask(request: request)
        isListening = true
        
        // Session rotation timer
        sessionRotationTimer = Timer.scheduledTimer(withTimeInterval: sessionRotationInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotateSession() }
        }
    }
    
    func stopListening() {
        sessionRotationTimer?.invalidate()
        sessionRotationTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
        lastProcessedWordCount = 0
    }
    
    // MARK: - Session Rotation
    
    private func rotateSession() {
        guard isListening else { return }
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        
        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.requiresOnDeviceRecognition = true
        self.recognitionRequest = newRequest
        self.lastProcessedWordCount = 0
        
        startRecognitionTask(request: newRequest)
    }
    
    private func startRecognitionTask(request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let segments = result.bestTranscription.segments
                let newSegments = Array(segments.dropFirst(self.lastProcessedWordCount))
                if !newSegments.isEmpty {
                    let words = newSegments.map {
                        RecognizedWord(text: $0.substring, timestamp: $0.timestamp, confidence: $0.confidence)
                    }
                    self.lastProcessedWordCount = segments.count
                    self.onWordsRecognized?(words)
                }
            }
            if let error {
                let nsError = error as NSError
                // Ignore cancellation errors from session rotation
                guard !(nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 209) else { return }
                print("[AppleSpeechProvider] Error: \(error)")
            }
        }
    }
    
    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        Task { @MainActor in self.audioLevel = min(max(rms * 5.0, 0.0), 1.0) }
    }
}
```

---

#### 3.1.4 Model Manager

Handles WhisperKit model discovery, download, storage, and lifecycle.

**Implementation: `ModelManager.swift`**

```swift
import Foundation
import WhisperKit

@MainActor
class ModelManager: ObservableObject {
    
    @Published var availableModels: [WhisperModel] = []
    @Published var downloadProgress: Double = 0.0  // 0.0–1.0
    @Published var isDownloading = false
    @Published var downloadedModels: Set<String> = []
    
    /// Where models are stored on disk
    private let modelsDirectory: URL
    
    struct WhisperModel: Identifiable {
        let id: String       // e.g. "base.en"
        let displayName: String
        let sizeDescription: String
        let sizeBytes: Int64
        let isDownloaded: Bool
        let isRecommended: Bool
    }
    
    init() {
        // Store models in Application Support, not caches (user explicitly downloads them)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsDirectory = appSupport.appendingPathComponent("CueFlow/WhisperModels", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        refreshAvailableModels()
    }
    
    // MARK: - Model Catalog
    
    func refreshAvailableModels() {
        let downloaded = scanDownloadedModels()
        self.downloadedModels = downloaded
        
        self.availableModels = [
            WhisperModel(
                id: "tiny.en",
                displayName: "Tiny (English)",
                sizeDescription: "~40 MB — Fastest, good accuracy",
                sizeBytes: 40_000_000,
                isDownloaded: downloaded.contains("tiny.en"),
                isRecommended: false
            ),
            WhisperModel(
                id: "base.en",
                displayName: "Base (English)",
                sizeDescription: "~150 MB — Best balance of speed & accuracy",
                sizeBytes: 150_000_000,
                isDownloaded: downloaded.contains("base.en"),
                isRecommended: true
            ),
            WhisperModel(
                id: "small.en",
                displayName: "Small (English)",
                sizeDescription: "~500 MB — Highest accuracy",
                sizeBytes: 500_000_000,
                isDownloaded: downloaded.contains("small.en"),
                isRecommended: false
            ),
        ]
    }
    
    // MARK: - Download
    
    /// Ensure a model is available locally. Downloads if needed. Returns path to model folder.
    func ensureModelAvailable(_ modelName: String) async throws -> String {
        let modelPath = modelsDirectory.appendingPathComponent(modelName)
        
        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath.path
        }
        
        // Download via WhisperKit's built-in model fetching
        isDownloading = true
        downloadProgress = 0.0
        
        defer {
            isDownloading = false
            refreshAvailableModels()
        }
        
        // WhisperKit handles downloading from the Argmax HuggingFace repo
        // and compiling CoreML models. This can take 1-5 minutes on first run.
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelsDirectory.path,
            verbose: false
        )
        
        // Initialize WhisperKit — this triggers model download + compilation
        let _ = try await WhisperKit(config)
        
        downloadProgress = 1.0
        return modelPath.path
    }
    
    /// Delete a downloaded model to free disk space
    func deleteModel(_ modelName: String) throws {
        let modelPath = modelsDirectory.appendingPathComponent(modelName)
        try FileManager.default.removeItem(at: modelPath)
        refreshAvailableModels()
    }
    
    // MARK: - Scan
    
    private func scanDownloadedModels() -> Set<String> {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path) else {
            return []
        }
        return Set(contents)
    }
    
    /// Total disk space used by downloaded models
    var totalDiskUsage: Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        
        return contents.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }
}
```

---

#### 3.1.5 Provider Selection Logic

At app startup, CueFlow chooses the best provider automatically:

```swift
// In AppState.swift or a dedicated factory

func createSpeechProvider(modelManager: ModelManager, settings: AppSettings) -> any SpeechProvider {
    
    // Check if running on Apple Silicon (required for fast WhisperKit inference)
    let isAppleSilicon: Bool = {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        // Apple Silicon Macs report "arm64" variants
        return machine.contains("arm64")
    }()
    
    if isAppleSilicon {
        // Primary: WhisperKit on Apple Silicon
        return WhisperKitProvider(
            modelManager: modelManager,
            model: settings.whisperModel // e.g. "base.en"
        )
    } else {
        // Fallback: SFSpeechRecognizer on Intel Macs
        return AppleSpeechProvider()
    }
}
```

**User override:** Settings UI should allow the user to manually switch between WhisperKit and Apple Speech, regardless of hardware detection. Some users may prefer Apple Speech for lower latency even on Apple Silicon.

### 3.2 Speech-to-Scroll Engine (The Hard Part)

This is the core algorithm: given a stream of recognized words, determine where the presenter is in the script and drive the scroll position.

**Algorithm: Sliding Window Fuzzy Match**

**Implementation: `SpeechToScrollEngine.swift`**

```swift
import Foundation
import Combine

class SpeechToScrollEngine: ObservableObject {
    
    // MARK: - Published State
    @Published var currentWordIndex: Int = 0    // Position in the script (word-level)
    @Published var currentSlideIndex: Int = 0   // Which slide we're on
    @Published var isPaused: Bool = false
    @Published var scrollProgress: Double = 0.0 // 0.0–1.0 overall progress
    
    // MARK: - Script Data
    private var scriptWords: [ScriptWord] = []  // Flattened, normalized word list
    private var slideBreakpoints: [Int] = []     // Word indices where slides change
    
    // MARK: - Matching Parameters
    private let lookAheadWindow = 30    // Words ahead of cursor to search
    private let lookBehindWindow = 5    // Words behind cursor (for corrections)
    private let minMatchConfidence = 0.6 // Minimum similarity threshold (0–1)
    private let consecutiveMatchesRequired = 2 // Require N consecutive matches to advance
    
    // MARK: - Internal State
    private var matchBuffer: [(scriptIndex: Int, speechWord: String)] = []
    private var lastMatchTime: Date = Date()
    private let silencePauseThreshold: TimeInterval // From settings
    
    struct ScriptWord {
        let text: String           // Normalized (lowercased, stripped punctuation)
        let original: String       // Original text for display
        let slideIndex: Int        // Which slide this word belongs to
        let globalIndex: Int       // Position in the flattened script
    }
    
    init(silencePauseThreshold: TimeInterval = 3.0) {
        self.silencePauseThreshold = silencePauseThreshold
    }
    
    // MARK: - Load Script
    
    /// Load a presentation's speaker notes into the engine
    func loadPresentation(_ presentation: Presentation) {
        var words: [ScriptWord] = []
        var breakpoints: [Int] = []
        
        for (slideIdx, slide) in presentation.slides.enumerated() {
            breakpoints.append(words.count)
            
            let noteWords = tokenize(slide.speakerNotes)
            for word in noteWords {
                words.append(ScriptWord(
                    text: normalize(word),
                    original: word,
                    slideIndex: slideIdx,
                    globalIndex: words.count
                ))
            }
        }
        
        self.scriptWords = words
        self.slideBreakpoints = breakpoints
        self.currentWordIndex = 0
        self.currentSlideIndex = 0
        self.matchBuffer = []
    }
    
    /// Load a freeform script (with optional section markers)
    func loadScript(_ script: Script) {
        var words: [ScriptWord] = []
        var breakpoints: [Int] = []
        
        for (sectionIdx, section) in script.sections.enumerated() {
            breakpoints.append(words.count)
            let sectionWords = tokenize(section.text)
            for word in sectionWords {
                words.append(ScriptWord(
                    text: normalize(word),
                    original: word,
                    slideIndex: sectionIdx,
                    globalIndex: words.count
                ))
            }
        }
        
        self.scriptWords = words
        self.slideBreakpoints = breakpoints
        self.currentWordIndex = 0
        self.currentSlideIndex = 0
    }
    
    // MARK: - Process Recognized Words
    
    /// Called by any SpeechProvider.onWordsRecognized callback
    func processRecognizedWords(_ words: [RecognizedWord]) {
        guard !isPaused, !scriptWords.isEmpty else { return }
        
        lastMatchTime = Date()
        
        for word in words {
            let normalizedSpeech = normalize(word.text)
            guard !normalizedSpeech.isEmpty else { continue }
            
            // Define search window
            let searchStart = max(0, currentWordIndex - lookBehindWindow)
            let searchEnd = min(scriptWords.count - 1, currentWordIndex + lookAheadWindow)
            
            guard searchStart <= searchEnd else { continue }
            
            // Find best match in the window
            var bestMatch: (index: Int, score: Double)? = nil
            
            for i in searchStart...searchEnd {
                let similarity = fuzzyMatch(normalizedSpeech, scriptWords[i].text)
                
                // Bias toward forward matches (prefer advancing)
                let positionBias = i >= currentWordIndex ? 0.1 : 0.0
                let adjustedScore = similarity + positionBias
                
                if adjustedScore > minMatchConfidence {
                    if bestMatch == nil || adjustedScore > bestMatch!.score {
                        bestMatch = (index: i, score: adjustedScore)
                    }
                }
            }
            
            if let match = bestMatch {
                matchBuffer.append((scriptIndex: match.index, speechWord: normalizedSpeech))
                
                // Require consecutive forward matches to prevent false jumps
                if matchBuffer.count >= consecutiveMatchesRequired {
                    let recentMatches = matchBuffer.suffix(consecutiveMatchesRequired)
                    let indices = recentMatches.map(\.scriptIndex)
                    
                    // Check that recent matches are roughly sequential (within 3 words of each other)
                    let isSequential = zip(indices, indices.dropFirst()).allSatisfy { $1 - $0 >= 0 && $1 - $0 <= 3 }
                    
                    if isSequential, let lastIndex = indices.last {
                        advanceTo(wordIndex: lastIndex)
                    }
                }
                
                // Trim buffer to prevent unbounded growth
                if matchBuffer.count > 20 {
                    matchBuffer = Array(matchBuffer.suffix(10))
                }
            }
        }
    }
    
    // MARK: - Manual Controls
    
    /// Re-anchor voice tracking at a specific word index (after manual scroll)
    func reanchor(at wordIndex: Int) {
        currentWordIndex = wordIndex
        matchBuffer = []
        updateSlideIndex()
    }
    
    /// Jump to a specific slide
    func jumpToSlide(_ slideIndex: Int) {
        guard slideIndex < slideBreakpoints.count else { return }
        reanchor(at: slideBreakpoints[slideIndex])
    }
    
    // MARK: - Private Helpers
    
    private func advanceTo(wordIndex: Int) {
        guard wordIndex >= currentWordIndex else { return } // Never go backward automatically
        currentWordIndex = wordIndex
        scrollProgress = Double(wordIndex) / Double(max(scriptWords.count - 1, 1))
        updateSlideIndex()
    }
    
    private func updateSlideIndex() {
        // Find which slide the current word belongs to
        for (i, breakpoint) in slideBreakpoints.enumerated().reversed() {
            if currentWordIndex >= breakpoint {
                if currentSlideIndex != i {
                    currentSlideIndex = i
                }
                break
            }
        }
    }
    
    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
    
    private func normalize(_ word: String) -> String {
        word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Jaro-Winkler similarity (better for short strings than Levenshtein)
    /// Returns 0.0 (no match) to 1.0 (exact match)
    private func fuzzyMatch(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        
        let aChars = Array(a)
        let bChars = Array(b)
        let matchDistance = max(aChars.count, bChars.count) / 2 - 1
        
        var aMatched = [Bool](repeating: false, count: aChars.count)
        var bMatched = [Bool](repeating: false, count: bChars.count)
        
        var matches: Double = 0
        var transpositions: Double = 0
        
        // Count matches
        for i in aChars.indices {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, bChars.count)
            for j in start..<end {
                guard !bMatched[j], aChars[i] == bChars[j] else { continue }
                aMatched[i] = true
                bMatched[j] = true
                matches += 1
                break
            }
        }
        
        guard matches > 0 else { return 0.0 }
        
        // Count transpositions
        var k = 0
        for i in aChars.indices {
            guard aMatched[i] else { continue }
            while !bMatched[k] { k += 1 }
            if aChars[i] != bChars[k] { transpositions += 1 }
            k += 1
        }
        
        let jaro = (matches / Double(aChars.count) +
                     matches / Double(bChars.count) +
                     (matches - transpositions / 2) / matches) / 3
        
        // Winkler modification: boost score for common prefix
        var prefix = 0
        for i in 0..<min(4, min(aChars.count, bChars.count)) {
            if aChars[i] == bChars[i] { prefix += 1 } else { break }
        }
        
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }
}
```

**Key gotchas for Claude Code to handle:**

1. **Homophones:** "their" / "there" / "they're" should all match each other. The fuzzy matcher handles this to some degree, but consider adding a homophone equivalence map for common pairs.
2. **Numbers:** Speech recognizer may output "twenty-three" while script says "23". Add a number normalization step.
3. **Presenter skips ahead:** If someone skips 3 slides, the look-ahead window (30 words) may not reach the new position. Implement a "lost tracking" state: after 10 seconds with no matches, expand search to the entire remaining script and re-anchor on the first strong match.
4. **Presenter goes back:** The engine only auto-advances forward. Going backward requires manual re-anchoring (hover + scroll + click).

### 3.3 Google Slides Integration

**API endpoints used:**

| Operation | Endpoint | Scope |
|-----------|----------|-------|
| List presentations | `GET drive/v3/files?q=mimeType='application/vnd.google-apps.presentation'` | `drive.readonly` |
| Get presentation | `GET slides/v1/presentations/{id}` | `presentations.readonly` |
| Get slide thumbnail | `GET slides/v1/presentations/{id}/pages/{pageId}/thumbnail` | `presentations.readonly` |

**OAuth 2.0 flow:**

```
Client ID: Registered in Google Cloud Console (CueFlow project)
Redirect URI: Custom URL scheme — cueflow://oauth/callback
Scopes:
  - https://www.googleapis.com/auth/presentations.readonly
  - https://www.googleapis.com/auth/drive.readonly
```

**Implementation: `GoogleAuthService.swift`**

```swift
import AuthenticationServices
import Foundation

class GoogleAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    
    private let clientID: String  // From GoogleService-Info.plist
    private let redirectURI = "cueflow://oauth/callback"
    private let scopes = [
        "https://www.googleapis.com/auth/presentations.readonly",
        "https://www.googleapis.com/auth/drive.readonly"
    ]
    
    private var accessToken: String? {
        get { KeychainHelper.read(key: "google_access_token") }
        set { KeychainHelper.save(key: "google_access_token", value: newValue) }
    }
    
    private var refreshToken: String? {
        get { KeychainHelper.read(key: "google_refresh_token") }
        set { KeychainHelper.save(key: "google_refresh_token", value: newValue) }
    }
    
    private var tokenExpiry: Date? {
        get {
            guard let data = KeychainHelper.readData(key: "google_token_expiry") else { return nil }
            return try? JSONDecoder().decode(Date.self, from: data)
        }
        set {
            guard let date = newValue,
                  let data = try? JSONEncoder().encode(date) else { return }
            KeychainHelper.saveData(key: "google_token_expiry", data: data)
        }
    }
    
    init(clientID: String) {
        self.clientID = clientID
        super.init()
        self.isAuthenticated = refreshToken != nil
    }
    
    // MARK: - OAuth Flow
    
    func signIn() async throws {
        let authURL = buildAuthURL()
        
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "cueflow"
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
        
        let code = try extractAuthCode(from: callbackURL)
        try await exchangeCodeForTokens(code: code)
        
        isAuthenticated = true
    }
    
    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        userEmail = nil
    }
    
    /// Returns a valid access token, refreshing if needed
    func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
        
        guard let refresh = refreshToken else {
            throw GoogleAuthError.notAuthenticated
        }
        
        try await refreshAccessToken(refreshToken: refresh)
        return accessToken!
    }
    
    // MARK: - Private
    
    private func buildAuthURL() -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }
    
    private func extractAuthCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.noAuthCode
        }
        return code
    }
    
    private func exchangeCodeForTokens(code: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        
        request.httpBody = body.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        self.accessToken = response.access_token
        self.refreshToken = response.refresh_token ?? self.refreshToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(response.expires_in - 60))
    }
    
    private func refreshAccessToken(refreshToken: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientID,
            "grant_type": "refresh_token",
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        
        request.httpBody = body.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        self.accessToken = response.access_token
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(response.expires_in - 60))
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.mainWindow ?? ASPresentationAnchor()
    }
    
    // MARK: - Types
    
    struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let token_type: String
    }
    
    enum GoogleAuthError: Error {
        case notAuthenticated
        case noAuthCode
        case tokenRefreshFailed
    }
}
```

**Implementation: `GoogleSlidesService.swift`**

```swift
import Foundation

class GoogleSlidesService {
    
    private let auth: GoogleAuthService
    private let baseURL = "https://slides.googleapis.com/v1"
    private let driveBaseURL = "https://www.googleapis.com/drive/v3"
    
    init(auth: GoogleAuthService) {
        self.auth = auth
    }
    
    // MARK: - List Recent Presentations
    
    func listPresentations(maxResults: Int = 20) async throws -> [PresentationSummary] {
        let token = try await auth.getValidToken()
        
        // Query Drive API for Google Slides files, ordered by last viewed
        var components = URLComponents(string: "\(driveBaseURL)/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "mimeType='application/vnd.google-apps.presentation' and trashed=false"),
            URLQueryItem(name: "orderBy", value: "viewedByMeTime desc"),
            URLQueryItem(name: "pageSize", value: "\(maxResults)"),
            URLQueryItem(name: "fields", value: "files(id,name,thumbnailLink,modifiedTime,viewedByMeTime)"),
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DriveFilesResponse.self, from: data)
        
        return response.files.map { file in
            PresentationSummary(
                id: file.id,
                title: file.name,
                thumbnailURL: file.thumbnailLink,
                lastModified: file.modifiedTime,
                lastViewed: file.viewedByMeTime
            )
        }
    }
    
    // MARK: - Fetch Full Presentation
    
    func fetchPresentation(id: String) async throws -> Presentation {
        let token = try await auth.getValidToken()
        
        let url = URL(string: "\(baseURL)/presentations/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let apiPresentation = try JSONDecoder().decode(APIPresentationResponse.self, from: data)
        
        // Extract slides with speaker notes
        var slides: [Slide] = []
        
        for (index, apiSlide) in (apiPresentation.slides ?? []).enumerated() {
            let title = extractSlideTitle(from: apiSlide)
            let speakerNotes = extractSpeakerNotes(from: apiSlide, presentation: apiPresentation)
            
            // Fetch thumbnail
            let thumbnailData = try await fetchThumbnail(
                presentationId: id,
                pageId: apiSlide.objectId,
                token: token
            )
            
            slides.append(Slide(
                slideIndex: index,
                title: title,
                speakerNotes: speakerNotes,
                thumbnailData: thumbnailData
            ))
        }
        
        return Presentation(
            id: id,
            title: apiPresentation.title ?? "Untitled",
            lastSynced: Date(),
            slides: slides
        )
    }
    
    // MARK: - Fetch Thumbnail
    
    private func fetchThumbnail(presentationId: String, pageId: String, token: String) async throws -> Data? {
        // Step 1: Get thumbnail URL from API
        var components = URLComponents(string: "\(baseURL)/presentations/\(presentationId)/pages/\(pageId)/thumbnail")!
        components.queryItems = [
            URLQueryItem(name: "thumbnailProperties.mimeType", value: "PNG"),
            URLQueryItem(name: "thumbnailProperties.thumbnailSize", value: "MEDIUM"),
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let thumbResponse = try JSONDecoder().decode(ThumbnailResponse.self, from: data)
        
        // Step 2: Download the actual image
        guard let imageURL = URL(string: thumbResponse.contentUrl) else { return nil }
        let (imageData, _) = try await URLSession.shared.data(from: imageURL)
        return imageData
    }
    
    // MARK: - Parse Helpers
    
    /// Speaker notes are in the notesPage → shapes → find BODY placeholder → text
    private func extractSpeakerNotes(from slide: APISlide, presentation: APIPresentationResponse) -> String {
        guard let notesPage = slide.slideProperties?.notesPage else { return "" }
        
        // The speaker notes shape ID is in notesPage.notesProperties.speakerNotesObjectId
        guard let notesShapeId = notesPage.notesProperties?.speakerNotesObjectId else { return "" }
        
        // Find the shape with that ID in the notes page's page elements
        guard let shape = notesPage.pageElements?.first(where: { $0.objectId == notesShapeId }),
              let textContent = shape.shape?.text else { return "" }
        
        // Concatenate all text runs
        return textContent.textElements?
            .compactMap { $0.textRun?.content }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private func extractSlideTitle(from slide: APISlide) -> String? {
        // Look for a TITLE or CENTERED_TITLE placeholder
        let titlePlaceholders: Set<String> = ["TITLE", "CENTERED_TITLE"]
        
        return slide.pageElements?
            .first(where: { element in
                guard let placeholder = element.shape?.placeholder else { return false }
                return titlePlaceholders.contains(placeholder.type ?? "")
            })
            .flatMap { $0.shape?.text?.textElements?
                .compactMap { $0.textRun?.content }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }
    
    // MARK: - API Response Types (Decodable)
    
    struct APIPresentationResponse: Decodable {
        let presentationId: String?
        let title: String?
        let slides: [APISlide]?
    }
    
    struct APISlide: Decodable {
        let objectId: String
        let pageElements: [APIPageElement]?
        let slideProperties: APISlideProperties?
    }
    
    struct APISlideProperties: Decodable {
        let notesPage: APINotesPage?
    }
    
    struct APINotesPage: Decodable {
        let notesProperties: APINotesProperties?
        let pageElements: [APIPageElement]?
    }
    
    struct APINotesProperties: Decodable {
        let speakerNotesObjectId: String?
    }
    
    struct APIPageElement: Decodable {
        let objectId: String?
        let shape: APIShape?
    }
    
    struct APIShape: Decodable {
        let placeholder: APIPlaceholder?
        let text: APITextContent?
    }
    
    struct APIPlaceholder: Decodable {
        let type: String?
    }
    
    struct APITextContent: Decodable {
        let textElements: [APITextElement]?
    }
    
    struct APITextElement: Decodable {
        let textRun: APITextRun?
    }
    
    struct APITextRun: Decodable {
        let content: String?
    }
    
    struct ThumbnailResponse: Decodable {
        let contentUrl: String
        let width: Int?
        let height: Int?
    }
    
    struct DriveFilesResponse: Decodable {
        let files: [DriveFile]
    }
    
    struct DriveFile: Decodable {
        let id: String
        let name: String
        let thumbnailLink: String?
        let modifiedTime: String?
        let viewedByMeTime: String?
    }
}
```

### 3.4 Window Manager — Screen-Share Exclusion

**Critical research finding:** `NSWindow.sharingType = .none` is now marked as **legacy** by Apple and **does not work** with ScreenCaptureKit on macOS 15+. ScreenCaptureKit captures the compositor framebuffer, meaning all visible windows are recorded regardless of the `sharingType` flag.

**What this means for CueFlow:** True screen-share invisibility is not reliably achievable on macOS 15+ with public APIs. However, the approach used by Moody (and others like GhostLayer) still works for **most** video conferencing apps because:

1. **Zoom, Google Meet, Teams** use `CGWindowListCreateImage` (legacy API) which **does** respect `sharingType = .none`
2. **FaceTime** and apps using ScreenCaptureKit **will** capture the window
3. Setting the window level to `assistiveTechHighWindow` combined with `sharingType = .none` provides the best current behavior

**Implementation: `WindowManager.swift`**

```swift
import AppKit
import SwiftUI

class WindowManager: ObservableObject {
    
    @Published var prompterWindow: NSPanel?
    @Published var currentPreset: WindowPreset = .notch
    @Published var isPrompting = false
    
    // MARK: - Create Prompter Window
    
    func createPrompterWindow<Content: View>(content: Content) {
        // Use NSPanel (subclass of NSWindow) for utility window behavior
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.nonactivatingPanel, .resizable, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        // Core overlay behavior
        panel.level = .init(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        panel.collectionBehavior = [
            .canJoinAllSpaces,     // Visible across all Spaces/desktops
            .stationary,           // Doesn't move with space transitions
            .fullScreenAuxiliary,  // Visible over full-screen apps
            .ignoresCycle          // Excluded from Cmd+Tab / window cycling
        ]
        
        // Screen-share exclusion (legacy API — works with Zoom/Meet/Teams)
        panel.sharingType = .none
        
        // Visual properties
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        
        // Keep on top but don't steal focus
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        
        // Set SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        panel.contentView = hostingView
        
        self.prompterWindow = panel
        applyPreset(currentPreset)
        panel.orderFrontRegardless()
    }
    
    // MARK: - Position Presets
    
    func applyPreset(_ preset: WindowPreset) {
        guard let window = prompterWindow, let screen = targetScreen(for: preset) else { return }
        
        currentPreset = preset
        let frame: NSRect
        
        switch preset {
        case .notch:
            // Position centered at top of screen, below menu bar / notch area
            let menuBarHeight: CGFloat = NSApplication.shared.mainMenu?.menuBarHeight ?? 24
            let notchInset: CGFloat = hasNotch(screen: screen) ? 32 : 0
            let topOffset = menuBarHeight + notchInset
            let width: CGFloat = min(500, screen.frame.width * 0.4)
            let height: CGFloat = 180
            let x = screen.frame.midX - width / 2
            let y = screen.frame.maxY - topOffset - height
            frame = NSRect(x: x, y: y, width: width, height: height)
            
        case .floating(let savedFrame):
            frame = savedFrame ?? NSRect(
                x: screen.frame.midX - 200,
                y: screen.frame.midY - 100,
                width: 400,
                height: 200
            )
            
        case .externalMonitor(let screenIndex):
            let targetScreen = NSScreen.screens.indices.contains(screenIndex)
                ? NSScreen.screens[screenIndex]
                : screen
            let width: CGFloat = min(600, targetScreen.frame.width * 0.4)
            let height: CGFloat = 200
            let x = targetScreen.frame.midX - width / 2
            let y = targetScreen.frame.maxY - 50 - height // Near top, below where webcam sits
            frame = NSRect(x: x, y: y, width: width, height: height)
        }
        
        window.setFrame(frame, display: true, animate: true)
    }
    
    // MARK: - Screen Detection
    
    private func targetScreen(for preset: WindowPreset) -> NSScreen? {
        switch preset {
        case .notch:
            return NSScreen.screens.first // Built-in display is typically first
        case .floating:
            return prompterWindow?.screen ?? NSScreen.main
        case .externalMonitor(let index):
            return NSScreen.screens.indices.contains(index) ? NSScreen.screens[index] : NSScreen.main
        }
    }
    
    /// Detect if a screen has a notch (MacBook Pro 2021+)
    /// Notch screens have safeAreaInsets.top > 0
    private func hasNotch(screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }
    
    // MARK: - Cleanup
    
    func closePrompterWindow() {
        prompterWindow?.close()
        prompterWindow = nil
        isPrompting = false
    }
}

// MARK: - Window Preset Enum

enum WindowPreset: Codable, Equatable {
    case notch
    case floating(savedFrame: NSRect?)
    case externalMonitor(screenIndex: Int)
}

extension NSRect: @retroactive Codable {
    // Codable conformance for saving custom positions
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: CGFloat].self)
        self.init(
            x: dict["x"] ?? 0,
            y: dict["y"] ?? 0,
            width: dict["width"] ?? 400,
            height: dict["height"] ?? 200
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([
            "x": origin.x,
            "y": origin.y,
            "width": size.width,
            "height": size.height
        ])
    }
}
```

---

## 4. Data Models

```swift
// MARK: - Presentation (imported from Google Slides)

struct Presentation: Identifiable, Codable {
    let id: String              // Google Slides presentation ID
    var title: String
    var lastSynced: Date
    var slides: [Slide]
}

struct Slide: Identifiable, Codable {
    var id: String { "\(slideIndex)" }
    let slideIndex: Int
    let title: String?
    let speakerNotes: String
    let thumbnailData: Data?    // PNG image data, cached locally
    
    var hasSpeakerNotes: Bool {
        !speakerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Script (freeform, non-Slides content)

struct Script: Identifiable, Codable {
    let id: UUID
    var title: String
    var sections: [ScriptSection]
    var createdAt: Date
    var updatedAt: Date
    
    var estimatedDuration: TimeInterval {
        let totalWords = sections.reduce(0) { $0 + $1.wordCount }
        return TimeInterval(totalWords) / 2.5 // ~150 WPM
    }
}

struct ScriptSection: Identifiable, Codable {
    let id: UUID
    var title: String?     // Optional section label
    var text: String
    
    var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
}

// MARK: - Prompter State

class PrompterState: ObservableObject {
    @Published var mode: PrompterMode = .idle
    @Published var currentWordIndex: Int = 0
    @Published var currentSlideIndex: Int = 0
    @Published var scrollProgress: Double = 0.0
    @Published var elapsedTime: TimeInterval = 0
    @Published var isPaused: Bool = false
    
    enum PrompterMode {
        case idle
        case countdown(remaining: Int)
        case prompting
        case paused
        case finished
    }
}

// MARK: - App Settings

struct AppSettings: Codable {
    
    // Appearance
    var fontSize: CGFloat = 32
    var fontFamily: String = "SF Pro Display"
    var textColor: CodableColor = CodableColor(r: 1, g: 1, b: 1, a: 1)  // White
    var backgroundColor: CodableColor = CodableColor(r: 0, g: 0, b: 0, a: 0.9) // Black 90%
    var backgroundOpacity: Double = 0.9
    var textAlignment: TextAlignment = .left
    var lineSpacing: CGFloat = 1.5
    var highlightCurrentLine: Bool = true
    var highlightColor: CodableColor = CodableColor(r: 1, g: 0.95, b: 0.7, a: 0.3) // Soft yellow
    
    // Behavior
    var scrollMode: ScrollMode = .voiceActivated
    var autoScrollSpeed: Int = 5        // 1–10, for auto mode only
    var micSensitivity: Int = 5         // 1–10
    var selectedMicDeviceUID: String?   // nil = system default
    var pauseOnSilence: Bool = true
    var silenceThreshold: TimeInterval = 3.0  // seconds
    var showVoiceBeam: Bool = true
    
    // Speech Engine
    var speechEngine: SpeechEngineChoice = .whisperKit
    var whisperModel: String = "base.en"  // "tiny.en", "base.en", or "small.en"
    
    // Presentation
    var countdownDuration: Int = 3      // 0 = disabled
    var countdownSound: Bool = false
    var showSlideThumbnails: Bool = true
    var thumbnailPosition: ThumbnailPosition = .left
    var thumbnailSize: ThumbnailSize = .medium
    var showSlideNumber: Bool = true
    var showElapsedTime: Bool = false
    var showRemainingTime: Bool = false
    
    // Window
    var windowPreset: WindowPreset = .notch
    var rememberLastPosition: Bool = true
    var lastWindowFrame: NSRect? = nil
    
    // Enums
    enum ScrollMode: String, Codable, CaseIterable {
        case voiceActivated = "Voice-Activated"
        case manual = "Manual"
        case auto = "Auto (Constant Speed)"
    }
    
    enum SpeechEngineChoice: String, Codable, CaseIterable {
        case whisperKit = "WhisperKit"
        case appleSpeech = "Apple Speech"
    }
    
    enum TextAlignment: String, Codable, CaseIterable {
        case left = "Left"
        case center = "Center"
    }
    
    enum ThumbnailPosition: String, Codable, CaseIterable {
        case left = "Left"
        case right = "Right"
    }
    
    enum ThumbnailSize: String, Codable, CaseIterable {
        case small = "Small"    // 80pt wide
        case medium = "Medium"  // 120pt wide
        case large = "Large"    // 160pt wide
        
        var width: CGFloat {
            switch self {
            case .small: return 80
            case .medium: return 120
            case .large: return 160
            }
        }
    }
    
    struct CodableColor: Codable {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
    }
    
    // MARK: - Persistence
    
    static let storageKey = "cueflow_settings"
    
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }
    
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
```

---

## 5. Info.plist Required Keys

```xml
<!-- Microphone access for voice-activated scrolling -->
<key>NSMicrophoneUsageDescription</key>
<string>CueFlow uses your microphone to scroll your script as you speak. Audio is processed entirely on your device and never sent to any server.</string>

<!-- Speech recognition -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>CueFlow uses speech recognition to match your spoken words to your script and automatically scroll to keep up with you. All recognition happens on-device.</string>

<!-- Custom URL scheme for Google OAuth callback -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>cueflow</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.cueflow.oauth</string>
    </dict>
</array>

<!-- Network access -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

---

## 6. Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Network access for Google APIs -->
    <key>com.apple.security.network.client</key>
    <true/>
    
    <!-- Microphone access -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
    
    <!-- Keychain access for OAuth tokens -->
    <key>com.apple.security.keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.cueflow.app</string>
    </array>
    
    <!-- NOTE: Do NOT enable App Sandbox for v1 (direct distribution).
         NSPanel window level manipulation required for always-on-top behavior
         is restricted under App Sandbox. Evaluate sandboxing for Mac App Store
         submission later. -->
</dict>
</plist>
```

---

## 7. Build & Distribution

**Target:** macOS 14.0+ (Sonoma)
**Architecture:** Universal (Apple Silicon + Intel)
**Signing:** Developer ID (for direct distribution outside Mac App Store)

### Distribution plan (v1):
1. **Payment processor:** LemonSqueezy or Gumroad — handles license keys + payments
2. **Packaging:** DMG with drag-to-Applications installer
3. **Auto-updates:** Sparkle framework (https://sparkle-project.org/) for in-app update checks
4. **Notarization:** Required for direct distribution — `xcrun notarytool submit`

### Google Cloud Console setup:
1. Create project "CueFlow"
2. Enable APIs: Google Slides API, Google Drive API
3. Create OAuth 2.0 Client ID (type: macOS / Desktop)
4. Set redirect URI: `cueflow://oauth/callback`
5. Configure consent screen (external, publishing status: testing initially)
6. Store Client ID in `Constants.swift` (NOT the client secret — desktop OAuth PKCE flow doesn't need it for public clients, but Google's desktop flow uses the client secret, so store it in the app bundle. This is acceptable for desktop apps per Google's docs.)

---

## 8. Implementation Priority (for Claude Code)

Build in this order — each phase is independently testable:

### Phase 1: Core Speech Engine (3–4 days)
1. `SpeechProvider.swift` — protocol definition + `RecognizedWord` type
2. `ModelManager.swift` — WhisperKit model download/management (test: download `tiny.en`, verify on disk)
3. `WhisperKitProvider.swift` — streaming inference from mic → recognized words
4. `AppleSpeechProvider.swift` — SFSpeechRecognizer fallback with session rotation
5. `SpeechToScrollEngine.swift` — fuzzy matching algorithm with unit tests
6. `FuzzyMatcher.swift` — Jaro-Winkler implementation with test suite
7. Test harness: minimal SwiftUI view that shows recognized words and matched script position
8. **Milestone:** speak at a script, see the cursor track your words in the console

### Phase 2: Prompter Overlay (2–3 days)
1. `WindowManager.swift` — NSPanel with always-on-top + screen-share exclusion
2. `PrompterOverlayView.swift` — scrolling text display driven by `currentWordIndex`
3. `VoiceBeamView.swift` — audio level visualization
4. `CountdownView.swift` — pre-start countdown
5. Wire speech engine → prompter scroll position
6. Test: load hardcoded script, speak, verify scroll tracking

### Phase 3: Google Slides Integration (2–3 days)
1. `GoogleAuthService.swift` — OAuth flow + Keychain token storage
2. `GoogleSlidesService.swift` — fetch presentations, parse speaker notes, download thumbnails
3. `SlidesPickerView.swift` — presentation browser UI
4. `SlideThumbnailView.swift` — thumbnail display in prompter
5. Test: authenticate, pick a real deck, verify notes + thumbnails load correctly

### Phase 4: Editor + Settings (2 days)
1. `ScriptEditorView.swift` — freeform text editor with section markers
2. Settings views — all four tabs (appearance, behavior, presentation, window)
3. `AppSettings.swift` — persistence via UserDefaults
4. Wire settings to prompter behavior (font size, colors, scroll mode, etc.)

### Phase 5: Onboarding + Polish (2–3 days)
1. Onboarding flow (welcome → mic permission → model download → Google connect → calibration)
2. Model download UI with progress bar (first-launch downloads `base.en`, ~150MB)
3. Settings: model picker with download/delete per model + disk usage display
4. Keyboard shortcuts (play/pause, scroll speed adjust, re-anchor)
5. Menu bar presence (optional quick-launch)
6. App icon and visual polish

### Phase 6: Distribution (1 day)
1. Sparkle integration for auto-updates
2. DMG packaging
3. Notarization pipeline
4. Landing page copy (can be generated separately)

---

## 9. Testing Strategy

### Unit Tests (Critical)
- `SpeechToScrollEngine`: Test with pre-recorded word sequences. Verify correct cursor advancement for exact matches, fuzzy matches (homophones), skipped words, and presenter ad-libs.
- `FuzzyMatcher`: Edge cases — empty strings, single characters, identical strings, completely different strings, homophones ("write"/"right"), numbers ("23" vs "twenty-three").
- `WhisperKitProvider`: Model loading, chunk processing, word deduplication across overlapping chunks, graceful error recovery on transient inference failures.
- `ModelManager`: Model download lifecycle, disk space tracking, model deletion.
- `GoogleSlidesService`: Mock API responses (provide sample JSON fixtures). Verify speaker notes extraction, thumbnail URL parsing, error handling.

### Integration Tests
- Speech → Scroll → UI: Verify that recognized speech drives the prompter view scroll offset.
- Google Auth → Fetch → Display: End-to-end import of a test presentation.

### Manual Test Matrix
- [ ] Voice tracking accuracy with quiet background
- [ ] Voice tracking with moderate background noise (fan, music)
- [ ] Screen-share invisibility in Zoom, Google Meet, Teams
- [ ] Screen-share behavior in FaceTime (expected: visible — document this)
- [ ] Window behavior across multiple Spaces
- [ ] Window behavior over full-screen apps
- [ ] External monitor positioning
- [ ] Notch detection on MacBook Pro vs. MacBook Air vs. external display
- [ ] Long session stability (30+ minute presentation)
- [ ] Session rotation (verify no audio gaps during SFSpeechRecognizer restart)

---

## 10. Open Questions & Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | `sharingType = .none` may stop working in future macOS versions entirely | Monitor Apple's ScreenCaptureKit evolution. File Feedback Assistant for "exclude window from screen capture" API. Implement a user-visible "Screen Share Mode" toggle so users understand the limitation. |
| 2 | WhisperKit `base.en` model accuracy may be insufficient for some accents or noisy environments | Offer `small.en` as a downloadable upgrade for higher accuracy. Add a calibration step during onboarding where user reads a paragraph and CueFlow measures recognition quality. If accuracy < threshold, recommend using a headset mic or upgrading the model. |
| 3 | Google OAuth consent screen requires verification for production (>100 users) | Submit for Google verification early (takes 4-6 weeks). Use "testing" mode for initial beta. |
| 4 | Mac App Store sandboxing blocks NSPanel window level manipulation | Ship v1 as direct distribution only. Investigate if `auxiliary` window level (lower than `assistiveTechHighWindow`) is acceptable within sandbox. |
| 5 | SpeechAnalyzer (macOS 26) is better than both WhisperKit and SFSpeechRecognizer but requires Tahoe | The `SpeechProvider` protocol already supports adding new engines. Implement `SpeechAnalyzerProvider` as a third option when macOS 26 adoption is sufficient. SpeechAnalyzer has no model download, no session limits, and native long-form support — it will be the best option once available. |
| 6 | Name "CueFlow" may be taken | Check domain, trademark, App Store before committing. Alternatives: PromptDeck, SlideCue, NoteCast, DeckFlow. |

---

## Appendix A: Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ Return` | Start / stop prompting |
| `Space` | Pause / resume |
| `↑ / ↓` | Manual scroll (when paused or in manual mode) |
| `⌘ ↑ / ⌘ ↓` | Previous / next slide |
| `⌘ +` / `⌘ -` | Increase / decrease font size |
| `⌘ ,` | Open settings |
| `Esc` | Close prompter overlay |
| `⌘ R` | Re-anchor voice tracking at current scroll position |

## Appendix B: Future Considerations (v2+)

- **SpeechAnalyzer provider:** When macOS 26 adoption is >50%, add a `SpeechAnalyzerProvider` — no model download, no session limits, native long-form support, lower latency than WhisperKit.
- **Whisper model fine-tuning:** WhisperKit supports custom models. Fine-tune on presentation-style speech (measured pace, technical vocabulary) for even better accuracy.
- **AI script expansion:** Take bullet points → expand to full natural script using LLM (on-device via Apple Intelligence or API call).
- **Pacing coach:** Real-time WPM display, filler word counter ("um", "uh", "like"), and post-session analytics.
- **Keynote / PowerPoint import:** AppleScript bridge for Keynote; `python-pptx`-style parsing for .pptx files.
- **Rehearsal mode:** Record a practice run, play back with visual diff against the script to show where you deviated.
- **Multi-language voice recognition:** WhisperKit supports multilingual Whisper models. Offer `base` (non-English-only) for international presenters.
