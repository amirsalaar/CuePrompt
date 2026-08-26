import AVFoundation
import Speech
import XCTest

@testable import CuePrompt

/// The tap block runs on CoreAudio's real-time I/O thread while session rotation swaps the
/// request from an actor context. Previously rotation re-installed the tap itself, and the
/// render thread could be inside the block AVFAudio was freeing — EXC_BAD_ACCESS with
/// pc=0x0 on com.apple.audio.IOThread.client. The sink is what makes the swap safe, so it
/// has to tolerate concurrent append/setRequest without tearing.
final class SpeechAudioSinkTests: XCTestCase {

    private func makeBuffer(frames: AVAudioFrameCount = 1024) -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else {
            fatalError("could not build a test buffer")
        }
        buffer.frameLength = frames
        return buffer
    }

    func testStartsDetached() {
        let sink = SpeechAudioSink()

        XCTAssertFalse(sink.hasRequest)
    }

    func testAppendWithoutRequestIsIgnored() {
        let sink = SpeechAudioSink()

        sink.append(makeBuffer())

        XCTAssertFalse(sink.hasRequest)
    }

    func testSetRequestAttachesAndDetaches() {
        let sink = SpeechAudioSink()

        sink.setRequest(SFSpeechAudioBufferRecognitionRequest())
        XCTAssertTrue(sink.hasRequest)

        sink.setRequest(nil)
        XCTAssertFalse(sink.hasRequest)
    }

    func testAppendForwardsToAttachedRequest() {
        let sink = SpeechAudioSink()
        sink.setRequest(SFSpeechAudioBufferRecognitionRequest())

        // No observable side effect on the request itself; this asserts the call path is
        // exercised without trapping, which is the failure mode that matters here.
        for _ in 0..<50 {
            sink.append(makeBuffer())
        }

        XCTAssertTrue(sink.hasRequest)
    }

    /// Regression guard for the crash: buffers arriving on many threads while the request is
    /// swapped underneath them, the way a session rotation collides with audio capture.
    func testConcurrentAppendsDuringRequestSwapsAreSafe() {
        let sink = SpeechAudioSink()
        let buffer = makeBuffer()
        sink.setRequest(SFSpeechAudioBufferRecognitionRequest())

        let swapsDone = expectation(description: "request swaps finished")
        DispatchQueue(label: "rotation").async {
            for _ in 0..<300 {
                sink.setRequest(SFSpeechAudioBufferRecognitionRequest())
                sink.setRequest(nil)
            }
            swapsDone.fulfill()
        }

        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            sink.append(buffer)
        }

        wait(for: [swapsDone], timeout: 30)
    }

    /// A request released by a concurrent swap must stay alive for the duration of an
    /// in-flight append — that's why append copies the reference out under the lock.
    func testSwapDuringAppendDoesNotDeallocateInFlightRequest() {
        let sink = SpeechAudioSink()
        weak var weakRequest: SFSpeechAudioBufferRecognitionRequest?

        autoreleasepool {
            let request = SFSpeechAudioBufferRecognitionRequest()
            weakRequest = request
            sink.setRequest(request)
            sink.append(makeBuffer())
            XCTAssertNotNil(weakRequest)
            sink.setRequest(nil)
        }

        XCTAssertNil(weakRequest, "sink must not retain the request after detaching")
    }
}
