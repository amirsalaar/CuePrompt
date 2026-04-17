import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.cueprompt.app", category: "debug")

/// Writes a debug line to /tmp/cueprompt-debug.log and os_log.
func debugLog(_ msg: String) {
    logger.info("\(msg)")
    let line = "\(Date()) \(msg)\n"
    let path = "/tmp/cueprompt-debug.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

/// Root application state. Owns all services and coordinates the app flow.
@Observable
final class AppState {

    // MARK: - Services

    let engine = SpeechToScrollEngine()
    let modelManager = ModelManager()
    let windowManager = WindowManager()
    let bridgeCoordinator = BridgeCoordinator()
    let prompterState = PrompterState()
    let permissionManager = PermissionManager()

    private(set) var speechCoordinator: SpeechCoordinator!
    var settings = AppSettings.load()

    /// Set when presenting is blocked by missing permissions.
    var showPermissionAlert = false

    // MARK: - State

    var currentContent: ContentIngestor.EngineContent?
    var scriptWords: [String] = []
    var scriptSections: [ScriptSection] = []

    // Timers
    private var tickTimer: Timer?  // 1s: lost tracking check + state update
    private var presentationStartTime: Date?
    private var pausedAt: Date?  // when pause started (for subtracting paused time)
    private var totalPausedTime: TimeInterval = 0
    private(set) var wasPausedBeforeCollapse: Bool = false

    init() {
        debugLog("[AppState] init")
        self.speechCoordinator = SpeechCoordinator(engine: engine, modelManager: modelManager)
        setupBridgeCallbacks()
    }

    // MARK: - Lifecycle

    func setup() {
        windowManager.setupPanel()
        modelManager.scanLocalModels()
        bridgeCoordinator.startListening()

        // Wire keyboard shortcuts for the prompter panel
        windowManager.onSpacePressed = { [weak self] in
            self?.togglePause()
        }
        windowManager.onArrowUp = { [weak self] in
            guard let self, self.prompterState.mode == .paused else { return }
            self.engine.nudge(by: -3)
        }
        windowManager.onArrowDown = { [weak self] in
            guard let self, self.prompterState.mode == .paused else { return }
            self.engine.nudge(by: 3)
        }
    }

    // MARK: - Content Loading

    func loadContent(_ content: ContentIngestor.EngineContent) {
        currentContent = content
        scriptWords = TextNormalizer.tokenize(content.scriptText)
        scriptSections = content.sections
        engine.loadScript(
            content.scriptText, sections: content.sections, slideBoundaries: content.slideBoundaries
        )
    }

    func loadFile(at url: URL) throws {
        let content = try ContentIngestor.ingestFile(at: url)
        loadContent(content)
    }

    func loadText(_ text: String) {
        let content = ContentIngestor.ingestText(text)
        loadContent(content)
    }

    func clearContent() {
        currentContent = nil
        scriptWords = []
        scriptSections = []
        engine.stop()
    }

    // MARK: - Prompting Flow

    /// Start presenting with simulated speech — for debug/testing.
    func startSimulatedPresenting() {
        guard currentContent != nil else { return }

        NSApplication.shared.mainWindow?.miniaturize(nil)
        prompterState.mode = .expanded
        windowManager.showPill(settings: settings)
        windowManager.expand(settings: settings)

        presentationStartTime = Date()
        totalPausedTime = 0
        pausedAt = nil

        // Feed script words to the engine via simulation
        speechCoordinator.startSimulating(words: scriptWords, wordsPerSecond: 3.0)
        startTickTimer()
    }

    func startPresenting() {
        guard currentContent != nil else { return }

        // Gate on permissions — refresh and check before starting
        permissionManager.refreshStatus()
        guard permissionManager.allGranted else {
            showPermissionAlert = true
            return
        }

        // Minimize the main window so it doesn't compete with the presentation
        NSApplication.shared.mainWindow?.miniaturize(nil)

        prompterState.mode = .countdown(remaining: settings.countdownDuration)
        windowManager.showPill(settings: settings)

        // Countdown sequence
        Task { @MainActor in
            for i in stride(from: settings.countdownDuration, through: 1, by: -1) {
                prompterState.mode = .countdown(remaining: i)
                try? await Task.sleep(for: .seconds(1))
            }

            // Start prompting
            if settings.autoExpandOnStart {
                prompterState.mode = .expanded
                windowManager.expand(settings: settings)
            } else {
                prompterState.mode = .collapsed
            }

            presentationStartTime = Date()
            totalPausedTime = 0
            pausedAt = nil
            speechCoordinator.startListening()
            startTickTimer()
        }
    }

    func stopPresenting() {
        speechCoordinator.stopListening()
        engine.stop()
        stopTickTimer()
        prompterState.mode = .finished

        if settings.collapseOnFinish {
            windowManager.collapse(settings: settings)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(settings.finishFadeDelay))
                windowManager.hide()
                prompterState.mode = .idle
            }
        }

        // Restore the main window
        for window in NSApplication.shared.windows where window.isMiniaturized {
            window.deminiaturize(nil)
        }
    }

    func togglePause() {
        if prompterState.mode == .paused {
            // Unpause — accumulate paused duration
            if let paused = pausedAt {
                totalPausedTime += Date().timeIntervalSince(paused)
                pausedAt = nil
            }
            engine.resume()
            prompterState.mode = .expanded
        } else if prompterState.isPresenting {
            pausedAt = Date()
            engine.pause()
            prompterState.mode = .paused
        }
    }

    func toggleExpandCollapse() {
        switch prompterState.mode {
        case .collapsed:
            prompterState.mode = wasPausedBeforeCollapse ? .paused : .expanded
            wasPausedBeforeCollapse = false
            windowManager.expand(settings: settings)
        case .paused:
            wasPausedBeforeCollapse = true
            prompterState.mode = .collapsed
            windowManager.collapse(settings: settings)
        case .expanded:
            wasPausedBeforeCollapse = false
            prompterState.mode = .collapsed
            windowManager.collapse(settings: settings)
        default:
            break
        }
    }

    // MARK: - Timers

    private func startTickTimer() {
        // 1-second timer for lost tracking checks, recovery, and state updates
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.checkLostTracking()
            if self.engine.isLost {
                self.engine.attemptRecovery()
            }
            self.updatePrompterState()
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func updatePrompterState() {
        prompterState.progress = engine.progress
        prompterState.currentSlideIndex = engine.currentSlideIndex
        // Elapsed time excludes paused duration
        if let start = presentationStartTime, prompterState.mode != .paused {
            prompterState.elapsedTime = Date().timeIntervalSince(start) - totalPausedTime
        }
        // Refresh the menubar menu with current state
        (NSApplication.shared.delegate as? AppDelegate)?.updateMenuBarMenu()
    }

    // MARK: - Bridge Callbacks

    private func setupBridgeCallbacks() {
        bridgeCoordinator.onPresentationUpdate = { [weak self] presentation in
            let content = ContentIngestor.ingest(presentation)
            self?.loadContent(content)
            self?.prompterState.totalSlides = presentation.totalSlides
        }

        bridgeCoordinator.onSlideChange = { [weak self] slideIndex in
            self?.prompterState.currentSlideIndex = slideIndex
        }
    }

    // MARK: - Settings

    func saveSettings() {
        settings.save()
    }
}
