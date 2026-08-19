import XCTest

@testable import CuePrompt

final class SpeechToScrollEngineTests: XCTestCase {

    private func makeEngine() -> SpeechToScrollEngine {
        SpeechToScrollEngine()
    }

    private func load(
        _ engine: SpeechToScrollEngine,
        text: String,
        slideBoundaries: [Int] = []
    ) {
        let script = Script.fromPlainText(text)
        engine.loadScript(script.fullText, sections: script.sections, slideBoundaries: slideBoundaries)
    }

    private func words(_ texts: [String], startTime: TimeInterval = 0) -> [RecognizedWord] {
        texts.enumerated().map { index, text in
            RecognizedWord(text: text, timestamp: startTime + Double(index) * 0.3, confidence: 0.9)
        }
    }

    func testInitialState() {
        let engine = makeEngine()

        XCTAssertEqual(engine.scrollPosition, 0)
        XCTAssertFalse(engine.isTracking)
        XCTAssertEqual(engine.currentSlideIndex, 0)
        XCTAssertEqual(engine.totalWords, 0)
        XCTAssertEqual(engine.progress, 0)
        XCTAssertFalse(engine.isLost)
    }

    func testLoadScriptStartsTracking() {
        let engine = makeEngine()
        load(engine, text: "Our revenue grew significantly last quarter")

        XCTAssertTrue(engine.isTracking)
        XCTAssertEqual(engine.scrollPosition, 0)
        XCTAssertEqual(engine.totalWords, 6)
        XCTAssertFalse(engine.isLost)
    }

    func testExactWordsAdvancePosition() {
        let engine = makeEngine()
        load(engine, text: "our revenue grew significantly last quarter")

        engine.processWords(words(["our", "revenue", "grew"]))

        XCTAssertEqual(engine.scrollPosition, 3)
        XCTAssertEqual(engine.progress, 0.5)
    }

    func testPrefixMatchAdvancesToNextWord() {
        let engine = makeEngine()
        load(engine, text: "perspective matters here")

        engine.processWords(words(["per"]))

        XCTAssertEqual(engine.scrollPosition, 1)
    }

    func testHomophoneNormalizationMatchesScript() {
        let engine = makeEngine()
        load(engine, text: "there revenue grew fast")

        engine.processWords(words(["their", "revenue", "grew"]))

        XCTAssertEqual(engine.scrollPosition, 3)
    }

    func testPauseIgnoresWordsUntilResume() {
        let engine = makeEngine()
        load(engine, text: "alpha bravo charlie delta")

        engine.pause()
        engine.processWords(words(["alpha", "bravo"]))
        XCTAssertEqual(engine.scrollPosition, 0)

        engine.resume()
        engine.processWords(words(["alpha", "bravo"]))
        XCTAssertEqual(engine.scrollPosition, 2)
    }

    func testStopPreventsFurtherTracking() {
        let engine = makeEngine()
        load(engine, text: "one two three four")

        engine.stop()
        engine.processWords(words(["one", "two", "three"]))

        XCTAssertFalse(engine.isTracking)
        XCTAssertEqual(engine.scrollPosition, 0)
    }

    func testResetClearsTrackingState() {
        let engine = makeEngine()
        load(engine, text: "one two three four five")
        engine.processWords(words(["one", "two", "three"]))
        engine.nudge(by: 1)

        engine.reset()

        XCTAssertEqual(engine.scrollPosition, 0)
        XCTAssertFalse(engine.isLost)
        XCTAssertEqual(engine.currentSlideIndex, 0)
    }

    func testNudgeUpdatesSlideIndex() {
        let engine = makeEngine()
        load(engine, text: "one two three four five six", slideBoundaries: [2, 4])

        engine.nudge(by: 4)

        XCTAssertEqual(engine.scrollPosition, 4)
        XCTAssertEqual(engine.currentSlideIndex, 2)
    }

    func testLostTrackingDetectionAndRecovery() {
        let engine = makeEngine()
        load(engine, text: "alpha bravo charlie delta echo foxtrot golf hotel")
        engine.lostTrackingTimeout = -1

        engine.checkLostTracking()
        XCTAssertTrue(engine.isLost)

        engine.attemptRecovery(recentWords: ["delta", "echo", "foxtrot"])

        XCTAssertFalse(engine.isLost)
        XCTAssertEqual(engine.scrollPosition, 6)
    }

    func testEmptyScriptIgnoresInputWithoutCrashing() {
        let engine = makeEngine()
        load(engine, text: "")

        engine.processWords(words(["hello", "world"]))

        XCTAssertEqual(engine.totalWords, 0)
        XCTAssertEqual(engine.scrollPosition, 0)
        XCTAssertEqual(engine.progress, 0)
    }

    func testRepeatedLoadScriptResetsPosition() {
        let engine = makeEngine()
        load(engine, text: "first script content here", slideBoundaries: [2])
        engine.nudge(by: 3)
        XCTAssertEqual(engine.currentSlideIndex, 1)

        load(engine, text: "second script different content entirely")

        XCTAssertEqual(engine.scrollPosition, 0)
        XCTAssertEqual(engine.totalWords, 5)
        XCTAssertEqual(engine.currentSlideIndex, 0)
    }

    // MARK: - Recovery Index Space
    //
    // The recovery index MUST be built with the same tokenization as `displayWords`,
    // because recovery writes its result straight into `cursorPosition`/`scrollPosition`.
    // `TextNormalizer.normalizeText` drops filler words and expands numbers, so a script
    // containing either produces a *shorter or longer* word array than the display split.

    /// A script whose filler words shrink the normalized array must still expose a
    /// recovery index in display-word space.
    func testRecoveryIndexWordCountMatchesDisplayWords() {
        let engine = makeEngine()
        load(engine, text: "um uh alpha bravo charlie delta echo foxtrot")

        XCTAssertEqual(engine.totalWords, 8)
        XCTAssertEqual(
            engine.recoveryIndexWordCount, engine.totalWords,
            "recovery index must be indexed like displayWords or positions/ranges desync")
    }

    /// Number expansion grows the normalized array; the index must not follow it.
    func testRecoveryIndexWordCountUnaffectedByNumberExpansion() {
        let engine = makeEngine()
        load(engine, text: "we grew 23 percent last quarter")

        XCTAssertEqual(engine.totalWords, 6)
        XCTAssertEqual(engine.recoveryIndexWordCount, engine.totalWords)
    }

    /// Regression: finishing a full speech leaves the cursor near `totalWords`. If the
    /// recovery index is shorter than the script, `cursorPosition..<wordCount` inverts and
    /// traps with "Range requires lowerBound <= upperBound".
    func testRecoveryNearEndOfScriptWithFillerWordsDoesNotTrap() {
        let engine = makeEngine()
        load(engine, text: "um uh alpha bravo charlie delta echo foxtrot")
        engine.lostTrackingTimeout = -1

        engine.nudge(by: 7)  // speaker reached the end of the script
        engine.checkLostTracking()
        XCTAssertTrue(engine.isLost)

        engine.attemptRecovery(recentWords: ["alpha", "bravo", "charlie"])

        XCTAssertLessThanOrEqual(engine.scrollPosition, Double(engine.totalWords))
        XCTAssertGreaterThanOrEqual(engine.scrollPosition, 0)
    }

    /// Recovery must land on the display word that follows the spoken phrase, not on the
    /// same ordinal in the filler-stripped array.
    func testRecoveryJumpsToDisplayWordPosition() {
        let engine = makeEngine()
        // display: 0=um 1=uh 2=alpha 3=bravo 4=charlie 5=delta 6=echo 7=foxtrot
        // filler-stripped: 0=alpha 1=bravo 2=charlie 3=delta 4=echo 5=foxtrot
        load(engine, text: "um uh alpha bravo charlie delta echo foxtrot")
        engine.lostTrackingTimeout = -1
        engine.checkLostTracking()

        engine.attemptRecovery(recentWords: ["alpha", "bravo", "charlie"])

        // "charlie" is display index 4, so the cursor belongs at 5 ("delta") — not 3.
        XCTAssertEqual(engine.scrollPosition, 5)
        XCTAssertFalse(engine.isLost)
    }

    /// A paused engine must not consume recovery: the 1s tick timer calls
    /// `attemptRecovery()` whenever `isLost` is set, including while paused.
    func testRecoveryIsIgnoredWhilePaused() {
        let engine = makeEngine()
        load(engine, text: "alpha bravo charlie delta echo foxtrot golf hotel")
        engine.lostTrackingTimeout = -1
        engine.checkLostTracking()
        XCTAssertTrue(engine.isLost)

        engine.pause()
        engine.attemptRecovery(recentWords: ["delta", "echo", "foxtrot"])

        XCTAssertEqual(engine.scrollPosition, 0, "paused engine must not jump the cursor")
        XCTAssertTrue(engine.isLost, "lost state should persist until resume")
    }

    /// Resuming must clear the stale silence so recovery doesn't fire immediately.
    func testResumeClearsLostTracking() {
        let engine = makeEngine()
        load(engine, text: "alpha bravo charlie delta echo foxtrot")
        engine.lostTrackingTimeout = -1
        engine.checkLostTracking()
        XCTAssertTrue(engine.isLost)

        engine.pause()
        engine.resume()

        XCTAssertFalse(engine.isLost)
    }
}
