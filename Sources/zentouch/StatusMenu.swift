import AppKit
import IOKit.hid

/// The menu bar icon: shows whether touch is working and lets you pause or quit without a terminal.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Pause Touch", action: #selector(togglePause), keyEquivalent: "")
    private let isPanelConnected: () -> Bool
    private let panelProblem: () -> String?
    private let onOpenPanel: () -> Void
    private let onPauseChange: (Bool) -> Void
    private var paused = false

    init(isPanelConnected: @escaping () -> Bool, panelProblem: @escaping () -> String?,
         onOpenPanel: @escaping () -> Void, onPauseChange: @escaping (Bool) -> Void) {
        self.isPanelConnected = isPanelConnected
        self.panelProblem = panelProblem
        self.onOpenPanel = onOpenPanel
        self.onPauseChange = onPauseChange
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(action("Gestures & Settings…", #selector(openPanel), key: ","))
        pauseItem.target = self
        menu.addItem(pauseItem)
        menu.addItem(action("Input Monitoring Settings…", #selector(openInputMonitoring)))
        menu.addItem(action("Accessibility Settings…", #selector(openAccessibility)))
        menu.addItem(.separator())
        menu.addItem(action("Quit ZenTouch", #selector(quit), key: "q"))
        item.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        statusLine.title = if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            "⚠︎ Needs Input Monitoring permission"
        } else if !CGPreflightPostEventAccess() {
            "⚠︎ Needs Accessibility permission"
        } else if let problem = panelProblem() {
            "⚠︎ \(problem)"
        } else if !isPanelConnected() {
            "Waiting for the ZenScreen…"
        } else if paused {
            "Touch paused"
        } else {
            "Touch active"
        }
        pauseItem.title = paused ? "Resume Touch" : "Pause Touch"
        let symbol = paused ? "hand.raised.slash" : "hand.point.up.left"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ZenTouch")
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func openPanel() { onOpenPanel() }

    @objc private func togglePause() {
        paused.toggle()
        onPauseChange(paused)
        refresh()
    }

    @objc private func openInputMonitoring() { openPrivacyPane("Privacy_ListenEvent") }
    @objc private func openAccessibility() { openPrivacyPane("Privacy_Accessibility") }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    // A clean exit; the LaunchAgent only restarts zentouch after a crash, so it stays quit until next login.
    @objc private func quit() { NSApp.terminate(nil) }
}
