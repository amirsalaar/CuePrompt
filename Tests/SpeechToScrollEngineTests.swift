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
}
