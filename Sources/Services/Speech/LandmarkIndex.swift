import Foundation

/// A match found in the script by the landmark index.
struct LandmarkMatch: Sendable {
    /// Position in the normalized script word array.
    let scriptWordIndex: Int
    /// Number of consecutive words matched (2 or 3).
    let length: Int
    /// Average similarity score across matched words.
    let score: Double

    func isStrong(threshold: Double = 0.85) -> Bool {
        length >= 3 && score >= threshold
    }

    func isWeak(threshold: Double = 0.70) -> Bool {
        length >= 2 && score >= threshold
    }
}

/// Pre-processes a script into an n-gram index for fast landmark detection.
///
/// Builds bigram (2-word) and trigram (3-word) indexes from the normalized script.
/// Common phrases are excluded from the bigram index to avoid ambiguous matches.
/// Trigrams are always indexed since 3-word phrases are rarely ambiguous.
final class LandmarkIndex: Sendable {

    /// Normalized words of the full script.
    let normalizedWords: [String]
    /// Total word count.
    let wordCount: Int

    // Exact-match indexes: "word1\tword2" -> [positions]
    private let bigramPositions: [String: [Int]]
    private let trigramPositions: [String: [Int]]
    // Single-word index for fuzzy fallback
    private let wordPositions: [String: [Int]]

    /// Common 2-word phrases that appear too often to be useful anchors.
    static let commonBigrams: Set<String> = [
        "and then", "so we", "the next", "and the", "in the",
        "of the", "to the", "on the", "is the", "it is",
        "we are", "we have", "that is", "this is", "their is",
        "i think", "going to", "want to", "need to",
        "have to", "able to", "a lot", "as well", "so that",
        "and so", "but the", "for the", "with the", "from the",
        "at the", "by the", "if we", "if you", "can we",
        "do you", "let me", "i am", "you are", "he is",
        "she is", "we will", "they are", "has been", "have been",
        "will be", "would be", "could be", "should be",
    ]

    /// Build an index from a raw script string.
    ///
    /// `TextNormalizer.normalizeText` drops filler words and expands numbers, so the
    /// resulting positions are in *its own* index space — they do NOT line up with a
    /// whitespace split of the same text. Callers that map positions back onto script
    /// words must use `init(normalizedWords:)` instead.
    convenience init(scriptText: String) {
        self.init(normalizedWords: TextNormalizer.normalizeText(scriptText))
    }

    /// Build an index over an already-tokenized word array, preserving its index space.
    ///
    /// Pass words that are 1:1 with the caller's own word list (e.g. the engine's
    /// `matchWords`) so that a returned `scriptWordIndex` is directly usable as a
    /// cursor position. Empty entries are kept so indices stay aligned.
    init(normalizedWords words: [String]) {
        self.normalizedWords = words
        self.wordCount = words.count

        var wordPos: [String: [Int]] = [:]
        var biPos: [String: [Int]] = [:]
        var triPos: [String: [Int]] = [:]

        for i in words.indices {
            wordPos[words[i], default: []].append(i)
        }

        for i in 0..<max(0, words.count - 1) {
            let key = "\(words[i])\t\(words[i + 1])"
            let readable = "\(words[i]) \(words[i + 1])"
            if !Self.commonBigrams.contains(readable) {
                biPos[key, default: []].append(i)
            }
        }

        for i in 0..<max(0, words.count - 2) {
            let key = "\(words[i])\t\(words[i + 1])\t\(words[i + 2])"
            triPos[key, default: []].append(i)
        }

        self.wordPositions = wordPos
        self.bigramPositions = biPos
        self.trigramPositions = triPos
    }

    /// Find landmark matches for spoken words within a search range of the script.
    ///
    /// Tries exact trigram/bigram matches first, then falls back to fuzzy matching
    /// within the search range.
    func findLandmarks(spokenWords: [String], searchRange: Range<Int>) -> [LandmarkMatch] {
        let normalized = spokenWords.map { TextNormalizer.normalize($0) }
        guard normalized.count >= 2 else { return [] }

        var matches: [LandmarkMatch] = []
        var matchedPositions: Set<Int> = []

        // Pass 1: Exact trigram matches
        for i in 0..<max(0, normalized.count - 2) {
            let key = "\(normalized[i])\t\(normalized[i + 1])\t\(normalized[i + 2])"
            if let positions = trigramPositions[key] {
                for pos in positions where searchRange.contains(pos) {
                    let match = LandmarkMatch(scriptWordIndex: pos, length: 3, score: 1.0)
                    matches.append(match)
                    matchedPositions.insert(pos)
                }
            }
        }

        // Pass 2: Exact bigram matches (skip if trigram already covers)
        for i in 0..<max(0, normalized.count - 1) {
            let key = "\(normalized[i])\t\(normalized[i + 1])"
            if let positions = bigramPositions[key] {
                for pos in positions where searchRange.contains(pos) {
                    guard !matchedPositions.contains(pos),
                          !matchedPositions.contains(pos - 1) else { continue }
                    matches.append(LandmarkMatch(scriptWordIndex: pos, length: 2, score: 1.0))
                }
            }
        }

        // Pass 3: Fuzzy matching within the search range (if no exact matches found)
        if matches.isEmpty {
            matches = fuzzySearchInRange(normalized: normalized, range: searchRange)
        }

        return matches
    }

    /// Brute-force fuzzy search within a limited range of the script.
    private func fuzzySearchInRange(normalized: [String], range: Range<Int>) -> [LandmarkMatch] {
        guard wordCount >= 2, normalized.count >= 2 else { return [] }
        let lo = max(0, range.lowerBound)
        let hi = min(wordCount, range.upperBound)
        guard lo < hi else { return [] }

        var bestMatch: LandmarkMatch?

        // For each consecutive pair of spoken words, slide over every script position in range
        for i in 0 ..< (normalized.count - 1) {
            var pos = lo
            while pos + 1 < hi, pos + 1 < wordCount {
                let s0 = FuzzyMatcher.similarity(normalized[i], normalizedWords[pos])
                if s0 > 0.6 {
                    let s1 = FuzzyMatcher.similarity(normalized[i + 1], normalizedWords[pos + 1])

                    // 3-word fuzzy trigram
                    if i + 2 < normalized.count, pos + 2 < wordCount {
                        let s2 = FuzzyMatcher.similarity(normalized[i + 2], normalizedWords[pos + 2])
                        let avg3 = (s0 + s1 + s2) / 3.0
                        if avg3 > 0.78, avg3 > (bestMatch?.score ?? 0) {
                            bestMatch = LandmarkMatch(scriptWordIndex: pos, length: 3, score: avg3)
                        }
                    }

                    // 2-word fuzzy bigram
                    let avg2 = (s0 + s1) / 2.0
                    if avg2 > 0.75 {
                        let bigramKey = "\(normalizedWords[pos]) \(normalizedWords[pos + 1])"
                        let isCommon = Self.commonBigrams.contains(bigramKey)
                        if !isCommon, bestMatch == nil || (avg2 > bestMatch!.score && (bestMatch!.length < 3)) {
                            bestMatch = LandmarkMatch(scriptWordIndex: pos, length: 2, score: avg2)
                        }
                    }
                }
                pos += 1
            }
        }

        if let m = bestMatch { return [m] }
        return []
    }
}
