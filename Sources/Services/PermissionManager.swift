import AVFoundation
import AppKit
import Speech

/// Centralized permission state for microphone and speech recognition.
///
/// Single source of truth — providers check status here instead of
/// requesting permissions themselves. Only onboarding and explicit
/// user actions trigger permission prompts.
@Observable
final class PermissionManager {

  enum Status: Equatable {
    case notDetermined
    case granted
    case denied
  }

  private(set) var microphoneStatus: Status = .notDetermined
  private(set) var speechRecognitionStatus: Status = .notDetermined

  var allGranted: Bool {
    microphoneStatus == .granted && speechRecognitionStatus == .granted
  }

  init() {
    refreshStatus()
  }

  /// Read-only refresh from system state. No prompts.
  func refreshStatus() {
    // Microphone
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: microphoneStatus = .granted
    case .denied, .restricted: microphoneStatus = .denied
    case .notDetermined: microphoneStatus = .notDetermined
    @unknown default: microphoneStatus = .notDetermined
    }

    // Speech recognition
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized: speechRecognitionStatus = .granted
    case .denied, .restricted: speechRecognitionStatus = .denied
    case .notDetermined: speechRecognitionStatus = .notDetermined
    @unknown default: speechRecognitionStatus = .notDetermined
    }
  }

  /// Request microphone permission. Returns true if granted.
  @MainActor
  func requestMicrophone() async -> Bool {
    if microphoneStatus == .granted { return true }

    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    microphoneStatus = granted ? .granted : .denied
    return granted
  }

  /// Request speech recognition permission. Returns true if granted.
  @MainActor
  func requestSpeechRecognition() async -> Bool {
    if speechRecognitionStatus == .granted { return true }

    let status = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
    speechRecognitionStatus = (status == .authorized) ? .granted : .denied
    return status == .authorized
  }

  /// Request all permissions sequentially. Returns true if all granted.
  @MainActor
  func requestAll() async -> Bool {
    let mic = await requestMicrophone()
    guard mic else { return false }
    let speech = await requestSpeechRecognition()
    return speech
  }

  /// Open System Settings to the relevant privacy pane(s).
  /// Note: x-apple.systempreferences: URLs are undocumented and may change across macOS versions.
  func openSystemSettings() {
    if microphoneStatus == .denied {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
      {
        NSWorkspace.shared.open(url)
      }
    }
    if speechRecognitionStatus == .denied {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
      {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
