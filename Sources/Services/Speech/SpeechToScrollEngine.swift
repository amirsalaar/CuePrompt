import Foundation

/// Forward-cursor speech tracking engine.
///
/// Matches spoken words against the script and advances a cursor position.
/// No drift — scroll only moves when speech matches. Pauses when you pause.
@Observable
final class SpeechToScrollEngine {

    // MARK: - Output State

    /// Current position in the script as a word index.
    private(set) var scrollPosition: Double = 0

    /// Whether the engine is actively tracking speech.
    private(set) var isTracking: Bool = false

    /// Current slide index based on scroll position and slide boundaries.
    private(set) var currentSlideIndex: Int = 0

    /// Total number of words in the loaded script.
    private(set) var totalWords: Int = 0

    /// Progress through the script (0.0 to 1.0).
    var progress: Double {
        guard totalWords > 0 else { return 0 }
        return min(1.0, scrollPosition / Double(totalWords))
    }

    /// Whether tracking has been lost (no match for > timeout).
    private(set) var isLost: Bool = false

    // MARK: - Configuration

    /// How many words ahead to search for a match (normal speech).
    var nearWindow: Int = 15

    /// How many words ahead to search for a match (skip detection).
    var wideWindow: Int = 50

    /// Minimum fuzzy similarity score to count as a match.
    var matchThreshold: Double = 0.75

    /// Seconds without a match before triggering recovery search.
    var lostTrackingTimeout: TimeInterval = 15

    // MARK: - Internal State

    /// Raw display words (same tokenization as PrompterTextView).
    /// Index space matches the text view's word positions.
    private var displayWords: [String] = []

    /// Normalized words for matching against speech (1:1 with displayWords).
    private var matchWords: [String] = []

    /// LandmarkIndex for recovery search after lost tracking.
    private var landmarkIndex: LandmarkIndex?

    private var slideBoundaries: [Int] = []
    private var cursorPosition: Int = 0
    private var lastMatchTime: Date = Date()
    private var isPaused: Bool = false

    /// Rolling buffer of recently spoken words for phrase matching.
    private var spokenBuffer: [String] = []
    private let maxBufferSize: Int = 6

    // MARK: - Public API

    /// Load a script for tracking. Resets all state.
    /// Uses sections to build word list — **must match PrompterTextView's tokenization exactly**.
    func loadScript(_ text: String, sections: [ScriptSection], slideBoundaries: [Int] = []) {
        // Build word list from sections: title words + body words, same order as text view
        var words: [String] = []
        for section in sections {
            if let title = section.title, !title.isEmpty {
                let titleWords = title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                words.append(contentsOf: titleWords)
            }
            let bodyWords = section.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            words.append(contentsOf: bodyWords)
        }

        displayWords = words
        // Normalized for speech matching — 1:1 with displayWords
        matchWords = displayWords.map { TextNormalizer.normalize($0) }

        landmarkIndex = LandmarkIndex(scriptText: text)
        self.slideBoundaries = slideBoundaries.sorted()
        totalWords = displayWords.count
        cursorPosition = 0
        scrollPosition = 0
        currentSlideIndex = 0
        isTracking = true
        isLost = false
        isPaused = false
        lastMatchTime = Date()
        spokenBuffer = []

        debugLog("[Engine] Loaded script: \(totalWords) display words, \(matchWords.count) match words")
    }

    /// Process incoming recognized words from the speech provider.
    func processWords(_ words: [RecognizedWord]) {
        guard isTracking, !isPaused else { return }

        for word in words {
            let cleaned = word.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .punctuationCharacters)
            guard !cleaned.isEmpty else { continue }

            // Filter WhisperKit artifacts
            let lower = cleaned.lowercased()
            if lower.hasPrefix("[") || lower.hasPrefix("(") || lower == "blank_audio"
                || lower == "blank" || lower == "audio" {
                continue
            }

            processOneWord(cleaned)
        }
    }

    /// Check for lost tracking. Call from a ~1 second timer.
    func checkLostTracking() {
        guard isTracking, !isPaused else { return }
        let elapsed = Date().timeIntervalSince(lastMatchTime)
        if elapsed > lostTrackingTimeout && !isLost {
            isLost = true
            debugLog("[Engine] Lost tracking after \(Int(elapsed))s — recovery search needed")
        }
    }

    /// Attempt recovery when tracking is lost. Uses the internal spoken buffer.
    func attemptRecovery() {
        attemptRecovery(recentWords: spokenBuffer)
    }

    /// Attempt recovery when tracking is lost. Called with recent speech buffer.
    func attemptRecovery(recentWords: [String]) {
        guard isLost, let index = landmarkIndex else { return }
        guard !recentWords.isEmpty else { return }

        // Search from current position forward through the entire script
        let searchRange = cursorPosition..<index.wordCount
        let matches = index.findLandmarks(spokenWords: recentWords, searchRange: searchRange)

        if let best = matches.first(where: { $0.isStrong(threshold: 0.80) }) {
            let newPos = best.scriptWordIndex + best.length
            debugLog("[Engine] Recovery: jumping to word \(newPos)")
            cursorPosition = newPos
            scrollPosition = Double(cursorPosition)
            lastMatchTime = Date()
            isLost = false
            spokenBuffer = [] // clear buffer to avoid stale phrase matches
            updateSlideIndex()
        } else {
            // Also try searching from the beginning if we haven't moved yet
            if cursorPosition > 0 {
                let fullRange = 0..<index.wordCount
                let fullMatches = index.findLandmarks(spokenWords: recentWords, searchRange: fullRange)
                if let best = fullMatches.first(where: { $0.isStrong(threshold: 0.80) }) {
                    let newPos = best.scriptWordIndex + best.length
                    debugLog("[Engine] Recovery (full scan): jumping to word \(newPos)")
                    cursorPosition = newPos
                    scrollPosition = Double(cursorPosition)
                    lastMatchTime = Date()
                    isLost = false
                    spokenBuffer = []
                    updateSlideIndex()
                }
            }
        }
    }

    /// Pause tracking.
    func pause() {
        isPaused = true
    }

    /// Resume tracking.
    func resume() {
        isPaused = false
        lastMatchTime = Date()
    }

    /// Manually nudge the scroll position (arrow keys while paused).
    func nudge(by amount: Double) {
        scrollPosition = max(0, min(scrollPosition + amount, Double(totalWords - 1)))
        cursorPosition = max(0, min(Int(scrollPosition), totalWords - 1))
        updateSlideIndex()
    }

    /// Stop tracking entirely.
    func stop() {
        isTracking = false
        isPaused = false
    }

    /// Reset to the beginning.
    func reset() {
        scrollPosition = 0
        cursorPosition = 0
        isLost = false
        lastMatchTime = Date()
        currentSlideIndex = 0
        spokenBuffer = []
    }

    // MARK: - Two-Layer Matching

    private func processOneWord(_ spoken: String) {
        let normalized = TextNormalizer.normalize(spoken)
        guard !normalized.isEmpty else { return }

        // Add to rolling phrase buffer
        spokenBuffer.append(normalized)
        if spokenBuffer.count > maxBufferSize {
            spokenBuffer.removeFirst()
        }

        debugLog("[Engine] word: \(normalized) buf: \(spokenBuffer) cursor: \(cursorPosition)")

        // Layer 1 — Phrase match (high confidence, prevents false jumps)
        // Try matching the last 3-5 spoken words as a consecutive sequence in the script.
        if spokenBuffer.count >= 3 {
            let searchEnd = min(cursorPosition + nearWindow + 10, totalWords)
            let searchStart = max(0, cursorPosition - 2) // allow slight backward correction
            if let matchEnd = findPhraseMatch(spokenBuffer, in: searchStart..<searchEnd) {
                advanceTo(matchEnd)
                return
            }
        }

        // Layer 2 — Single-word match for the next few words.
        // Exact match first, then prefix match (e.g. "per" for "perspective"
        // when Apple Speech sends a partial before going silent).
        let immediateEnd = min(cursorPosition + 5, totalWords)
        for i in cursorPosition..<immediateEnd {
            if matchWords[i] == normalized {
                advanceTo(i + 1)
                return
            }
        }
        // Prefix: spoken word is 3+ chars and is a prefix of the next script word
        if normalized.count >= 3 {
            for i in cursorPosition..<immediateEnd {
                if matchWords[i].hasPrefix(normalized) && matchWords[i].count > normalized.count {
                    debugLog("[Engine] Prefix match: \"\(normalized)\" → \"\(matchWords[i])\" at \(i)")
                    advanceTo(i + 1)
                    return
                }
            }
        }

        // No match — hold position. Speaker is ad-libbing, pausing, or was misrecognized.
    }

    /// Find where a spoken phrase matches consecutive words in the script.
    /// Returns the script position AFTER the last matched word.
    private func findPhraseMatch(_ phrase: [String], in searchRange: Range<Int>) -> Int? {
        guard searchRange.count >= 3 else { return nil }

        // Try different phrase lengths: prefer longer (more confident)
        // Start with the full buffer, then try shorter subsequences
        for phraseLen in stride(from: min(phrase.count, 5), through: 3, by: -1) {
            let subPhrase = Array(phrase.suffix(phraseLen))
            let maxStart = searchRange.upperBound - phraseLen
            guard maxStart >= searchRange.lowerBound else { continue }

            var bestStart: Int?
            var bestScore: Int = 0
            let requiredMatches = phraseLen <= 3 ? phraseLen : phraseLen - 1 // allow 1 miss for longer phrases

            for scriptStart in searchRange.lowerBound...maxStart {
                var matches = 0
                for j in 0..<phraseLen {
                    let scriptWord = matchWords[scriptStart + j]
                    let spokenWord = subPhrase[j]
                    if scriptWord == spokenWord {
                        matches += 1
                    } else if spokenWord.count >= 3 && scriptWord.count >= 3
                                && FuzzyMatcher.similarity(spokenWord, scriptWord) > 0.80 {
                        matches += 1
                    }
                }
                if matches >= requiredMatches && matches > bestScore {
                    bestScore = matches
                    bestStart = scriptStart
                }
            }

            if let start = bestStart {
                debugLog("[Engine] Phrase(\(phraseLen)) matched at \(start): \"\(subPhrase.joined(separator: " "))\"")
                return start + phraseLen
            }
        }

        return nil
    }

    private func advanceTo(_ position: Int) {
        cursorPosition = min(position, totalWords)
        scrollPosition = Double(cursorPosition)
        lastMatchTime = Date()
        isLost = false
        if let last = spokenBuffer.last {
            spokenBuffer = [last]
        } else {
            spokenBuffer = []
        }
        updateSlideIndex()
    }

    // MARK: - Slide Tracking

    private func updateSlideIndex() {
        guard !slideBoundaries.isEmpty else { return }
        let pos = Int(scrollPosition)
        var slideIdx = 0
        for boundary in slideBoundaries {
            if pos >= boundary {
                slideIdx += 1
            } else {
                break
            }
        }
        currentSlideIndex = slideIdx
    }
}
