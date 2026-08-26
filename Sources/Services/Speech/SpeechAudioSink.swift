import AVFoundation
import Speech

/// Thread-safe holder for the recognition request that the audio tap feeds.
///
/// The tap block runs on CoreAudio's real-time I/O thread. Swapping the tap itself while
/// the engine is running is a use-after-free — AVFAudio frees the old block on its
/// RealtimeMessenger queue while the render thread can still be dispatching through it,
/// which lands as `EXC_BAD_ACCESS` with `pc: 0x0` on `com.apple.audio.IOThread.client`.
///
/// So the tap is installed exactly once for the engine's lifetime and only this reference
/// changes when a session rotates.
final class SpeechAudioSink: @unchecked Sendable {

    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    /// Point the tap at a new request, or `nil` to drop buffers (during a rotation gap, or
    /// once `endAudio()` has been called — appending after that is invalid).
    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    /// Whether a request is currently attached.
    var hasRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return request != nil
    }

    /// Forward a captured buffer. Called on the audio I/O thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        // Copy the reference out under the lock, then append outside it. ARC keeps the
        // request alive for the duration of the call, so a concurrent setRequest() can
        // never deallocate it mid-append, and the lock is held only for a pointer read.
        lock.lock()
        let current = request
        lock.unlock()

        current?.append(buffer)
    }
}
