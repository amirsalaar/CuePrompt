import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.word.spacing", accessibilityDescription: "CuePrompt")
        }
        updateMenuBarMenu()
    }

    func updateMenuBarMenu() {
        let menu = NSMenu()

        if let state = appState, state.prompterState.isActive {
            let slideInfo = "Slide \(state.prompterState.currentSlideIndex + 1)/\(state.prompterState.totalSlides)"
            let elapsed = formatTime(state.prompterState.elapsedTime)
            let statusItem = NSMenuItem(title: "\(slideInfo)  ·  \(elapsed)", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(NSMenuItem.separator())

            let pauseTitle = state.prompterState.mode == .paused ? "Resume" : "Pause"
            menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "p"))
            menu.addItem(NSMenuItem(title: "Stop Presenting", action: #selector(stopPresenting), keyEquivalent: ""))
        } else {
            let presentItem = NSMenuItem(title: "Present", action: #selector(startPresenting), keyEquivalent: "\r")
            presentItem.isEnabled = appState?.currentContent != nil
            menu.addItem(presentItem)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit CuePrompt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        // Fix: quit should target the app
        menu.items.last?.target = NSApplication.shared

        self.statusItem?.menu = menu
    }

    @objc private func startPresenting() {
        appState?.startPresenting()
    }

    @objc private func stopPresenting() {
        appState?.stopPresenting()
    }

    @objc private func togglePause() {
        appState?.togglePause()
    }

    @objc private func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            if window is NSPanel { continue }
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // macOS 14+ direct call — avoids responder chain issues when no window is key
        NSApp.perform(Selector(("showSettingsWindow:")), with: nil)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        AppConstants.formatTime(seconds)
    }
}
