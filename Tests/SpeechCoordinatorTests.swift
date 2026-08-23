import XCTest

@testable import CuePrompt

/// Minimal stand-in for a real recognizer: records whether it was asked to stop.
private final class StubSpeechProvider: SpeechProvider, @unchecked Sendable {
    let name = "Stub"
    private(set) var isListening = false
    private(set) var stopCount = 0

    func startListening() async throws -> AsyncStream<[RecognizedWord]> {
        isListening = true
        return AsyncStream { $0.finish() }
    }

    func stopListening() async {
        stopCount += 1
        isListening = false
    }
}

final class SpeechCoordinatorTests: XCTestCase {

    private func makeCoordinator() -> SpeechCoordinator {
        SpeechCoordinator(engine: SpeechToScrollEngine(), modelManager: ModelManager())
    }

    /// Regression: `stopListening` used to read `activeProvider` inside a detached Task, so
    /// a stop immediately followed by a start (switchProvider, or pause/resume) resolved
    /// the *new* provider and shut it down — the app stayed "listening" but heard nothing.
    func testStopListeningDetachesProviderSynchronously() {
        let coordinator = makeCoordinator()
        coordinator.activeProvider = StubSpeechProvider()

        coordinator.stopListening()

        XCTAssertNil(
            coordinator.activeProvider,
            "provider must be detached before suspending, so a later start isn't clobbered")
    }

    /// A provider installed after a stop must survive the earlier stop's async teardown.
    func testProviderInstalledAfterStopIsNotTornDown() async throws {
        let coordinator = makeCoordinator()
        let outgoing = StubSpeechProvider()
        coordinator.activeProvider = outgoing

        coordinator.stopListening()
        let incoming = StubSpeechProvider()
        coordinator.activeProvider = incoming

        // Let the detached teardown Task run.
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(outgoing.stopCount, 1, "the departing provider should be stopped")
        XCTAssertEqual(incoming.stopCount, 0, "the incoming provider must be left alone")
        XCTAssertNotNil(coordinator.activeProvider)
    }

    func testStopListeningClearsListeningFlag() {
        let coordinator = makeCoordinator()
        coordinator.activeProvider = StubSpeechProvider()

        coordinator.stopListening()

        XCTAssertFalse(coordinator.isListening)
    }
}
